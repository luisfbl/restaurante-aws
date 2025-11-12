#!/bin/bash
set -uo pipefail

AWS_REGION="us-east-1"
AWS_ENDPOINT="http://localstack:4566"
TABLE_NAME="Pedidos"
QUEUE_NAME="pedidos"
BUCKET_NAME="comprovantes-pedidos"
TOPIC_NAME="PedidosConcluidos"
QUEUE_URL="$AWS_ENDPOINT/000000000000/$QUEUE_NAME"
TMP_ZIP_DIR="/tmp/localstack-lambdas"
mkdir -p "$TMP_ZIP_DIR"

# Criar tabela DynamoDB se não existir
if ! awslocal dynamodb describe-table --table-name "$TABLE_NAME" --region "$AWS_REGION" &>/dev/null; then
  echo "Criando tabela DynamoDB: $TABLE_NAME"
  awslocal dynamodb create-table \
    --table-name "$TABLE_NAME" \
    --attribute-definitions AttributeName=id,AttributeType=S \
    --key-schema AttributeName=id,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "$AWS_REGION"
else
  echo "Tabela DynamoDB já existe: $TABLE_NAME"
fi

# Criar fila SQS se não existir
if ! awslocal sqs get-queue-url --queue-name "$QUEUE_NAME" --region "$AWS_REGION" &>/dev/null; then
  echo "Criando fila SQS: $QUEUE_NAME"
  awslocal sqs create-queue \
    --queue-name "$QUEUE_NAME" \
    --region "$AWS_REGION"
else
  echo "Fila SQS já existe: $QUEUE_NAME"
fi

# Criar tópico SNS se não existir
if ! awslocal sns list-topics --region "$AWS_REGION" | grep -q "$TOPIC_NAME"; then
  echo "Criando tópico SNS: $TOPIC_NAME"
  TOPIC_ARN=$(awslocal sns create-topic \
    --name "$TOPIC_NAME" \
    --region "$AWS_REGION" \
    --query 'TopicArn' \
    --output text)
else
  echo "Tópico SNS já existe: $TOPIC_NAME"
  TOPIC_ARN=$(awslocal sns list-topics --region "$AWS_REGION" --query "Topics[?contains(TopicArn, '$TOPIC_NAME')].TopicArn" --output text)
fi

# Criar bucket S3 se não existir
if ! awslocal s3 ls "s3://$BUCKET_NAME" --region "$AWS_REGION" &>/dev/null; then
  echo "Criando bucket S3: $BUCKET_NAME"
  awslocal s3 mb "s3://$BUCKET_NAME" --region "$AWS_REGION"
else
  echo "Bucket S3 já existe: $BUCKET_NAME"
fi

# Criar função Lambda criar-pedido se não existir
if ! awslocal lambda get-function --function-name criar-pedido --region "$AWS_REGION" &>/dev/null; then
  echo "Criando função Lambda: criar-pedido"
  cp /etc/localstack/init/ready.d/lambda/criar_pedido.py "$TMP_ZIP_DIR"
  pushd "$TMP_ZIP_DIR" >/dev/null
  zip -q criar_pedido.zip criar_pedido.py
  popd >/dev/null
  awslocal lambda create-function \
    --function-name criar-pedido \
    --runtime python3.11 \
    --handler criar_pedido.lambda_handler \
    --role arn:aws:iam::000000000000:role/lambda-role \
    --zip-file fileb://$TMP_ZIP_DIR/criar_pedido.zip \
    --region "$AWS_REGION" \
    --timeout 60 \
    --environment "Variables={AWS_ENDPOINT_URL=$AWS_ENDPOINT,AWS_REGION=$AWS_REGION,DYNAMODB_TABLE=$TABLE_NAME,SQS_QUEUE_URL=$QUEUE_URL}"
else
  echo "Função Lambda já existe: criar-pedido"
fi

# Criar função Lambda processar-pedido se não existir
if ! awslocal lambda get-function --function-name processar-pedido --region "$AWS_REGION" &>/dev/null; then
  echo "Criando função Lambda: processar-pedido"
  cp /etc/localstack/init/ready.d/lambda/processar_pedido.py "$TMP_ZIP_DIR"
  pushd "$TMP_ZIP_DIR" >/dev/null
  zip -q processar_pedido.zip processar_pedido.py
  popd >/dev/null
  awslocal lambda create-function \
    --function-name processar-pedido \
    --runtime python3.11 \
    --handler processar_pedido.handler \
    --role arn:aws:iam::000000000000:role/lambda-role \
    --zip-file fileb://$TMP_ZIP_DIR/processar_pedido.zip \
    --region "$AWS_REGION" \
    --timeout 60 \
    --environment "Variables={AWS_ENDPOINT_URL=$AWS_ENDPOINT,AWS_REGION=$AWS_REGION,DYNAMODB_TABLE=$TABLE_NAME,S3_BUCKET_NAME=$BUCKET_NAME,SNS_TOPIC_ARN=$TOPIC_ARN}"
else
  echo "Função Lambda já existe: processar-pedido"
fi

# Criar API Gateway se não existir
if ! awslocal apigateway get-rest-apis --region "$AWS_REGION" | grep -q "pedidos-api"; then
  echo "Criando API Gateway: pedidos-api"
  API_ID=$(awslocal apigateway create-rest-api \
    --name pedidos-api \
    --region "$AWS_REGION" \
    --query 'id' \
    --output text)

  ROOT_RESOURCE=$(awslocal apigateway get-resources \
    --rest-api-id "$API_ID" \
    --region "$AWS_REGION" \
    --query 'items[0].id' \
    --output text)

  RESOURCE_ID=$(awslocal apigateway create-resource \
    --rest-api-id "$API_ID" \
    --parent-id "$ROOT_RESOURCE" \
    --path-part pedidos \
    --region "$AWS_REGION" \
    --query 'id' \
    --output text)

  awslocal apigateway put-method \
    --rest-api-id "$API_ID" \
    --resource-id "$RESOURCE_ID" \
    --http-method POST \
    --authorization-type NONE \
    --region "$AWS_REGION"

  awslocal apigateway put-integration \
    --rest-api-id "$API_ID" \
    --resource-id "$RESOURCE_ID" \
    --http-method POST \
    --type AWS_PROXY \
    --integration-http-method POST \
    --uri arn:aws:apigateway:$AWS_REGION:lambda:path/2015-03-31/functions/arn:aws:lambda:$AWS_REGION:000000000000:function:criar-pedido/invocations \
    --region "$AWS_REGION"

  awslocal apigateway create-deployment \
    --rest-api-id "$API_ID" \
    --stage-name dev \
    --region "$AWS_REGION"

  echo "API Gateway criado com ID: $API_ID"
else
  echo "API Gateway já existe: pedidos-api"
  API_ID=$(awslocal apigateway get-rest-apis --region "$AWS_REGION" --query "items[?name=='pedidos-api'].id" --output text)
fi

# Criar event source mapping se não existir
QUEUE_ARN=$(awslocal sqs get-queue-attributes \
  --queue-url "$QUEUE_URL" \
  --attribute-names QueueArn \
  --region "$AWS_REGION" \
  --query 'Attributes.QueueArn' \
  --output text)

if ! awslocal lambda list-event-source-mappings --function-name processar-pedido --region "$AWS_REGION" | grep -q "$QUEUE_ARN"; then
  echo "Criando event source mapping para processar-pedido"
  awslocal lambda create-event-source-mapping \
    --event-source-arn "$QUEUE_ARN" \
    --function-name processar-pedido \
    --batch-size 1 \
    --region "$AWS_REGION"
else
  echo "Event source mapping já existe para processar-pedido"
fi

echo "Inicialização concluída com sucesso!"
