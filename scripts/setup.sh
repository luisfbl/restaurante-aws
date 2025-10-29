#!/bin/bash
set -e

echo "🧼 Limpando artefatos anteriores..."
rm -f criarPedido.zip processarPedido.zip

echo "📦 Empacotando funções Lambda..."
zip -r criarPedido.zip backend/criarPedido > /dev/null
zip -r processarPedido.zip backend/processarPedido > /dev/null
echo "✅ Lambdas empacotadas!"

echo "🔧 Criando recursos AWS no LocalStack..."
# DynamoDB
awslocal dynamodb create-table \
  --table-name Pedidos \
  --attribute-definitions AttributeName=id,AttributeType=S \
  --key-schema AttributeName=id,KeyType=HASH \
  --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 || true

# SQS
awslocal sqs create-queue --queue-name fila-pedidos || true

# S3
awslocal s3 mb s3://comprovantes || true

echo "🚀 Criando funções Lambda..."

awslocal lambda create-function \
  --function-name CriarPedido \
  --runtime nodejs18.x \
  --handler index.handler \
  --zip-file fileb://criarPedido.zip \
  --role arn:aws:iam::000000000000:role/lambda-role || true

awslocal lambda create-function \
  --function-name ProcessarPedido \
  --runtime nodejs18.x \
  --handler index.handler \
  --zip-file fileb://processarPedido.zip \
  --role arn:aws:iam::000000000000:role/lambda-role || true

echo "🌐 Criando API Gateway e integrando com Lambda CriarPedido..."

# API
API_ID=$(awslocal apigateway create-rest-api \
  --name "RestauranteAPI" \
  --query 'id' \
  --output text)

ROOT_ID=$(awslocal apigateway get-resources \
  --rest-api-id "$API_ID" \
  --query 'items[0].id' \
  --output text)

PEDIDO_RESOURCE_ID=$(awslocal apigateway create-resource \
  --rest-api-id "$API_ID" \
  --parent-id "$ROOT_ID" \
  --path-part pedidos \
  --query 'id' \
  --output text)

awslocal apigateway put-method \
  --rest-api-id "$API_ID" \
  --resource-id "$PEDIDO_RESOURCE_ID" \
  --http-method POST \
  --authorization-type "NONE"

awslocal apigateway put-integration \
  --rest-api-id "$API_ID" \
  --resource-id "$PEDIDO_RESOURCE_ID" \
  --http-method POST \
  --type AWS_PROXY \
  --integration-http-method POST \
  --uri arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:000000000000:function:CriarPedido/invocations

awslocal lambda add-permission \
  --function-name CriarPedido \
  --statement-id apigateway-test-permission \
  --action lambda:InvokeFunction \
  --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:us-east-1:000000000000:$API_ID/*/POST/pedidos" || true

awslocal apigateway create-deployment \
  --rest-api-id "$API_ID" \
  --stage-name local > /dev/null

echo "🔗 Conectando SQS com Lambda ProcessarPedido..."

QUEUE_URL=$(awslocal sqs get-queue-url --queue-name fila-pedidos --query 'QueueUrl' --output text)
QUEUE_ARN=$(awslocal sqs get-queue-attributes \
  --queue-url "$QUEUE_URL" \
  --attribute-name QueueArn \
  --query 'Attributes.QueueArn' \
  --output text)

awslocal lambda create-event-source-mapping \
  --function-name ProcessarPedido \
  --event-source-arn "$QUEUE_ARN" \
  --batch-size 1 \
  --enabled || true

echo ""
echo "🎉 DEPLOY CONCLUÍDO COM SUCESSO!"
echo "🔗 Endpoint disponível:"
echo "POST http://localhost:4566/restapis/$API_ID/local/_user_request_/pedidos"
echo "Use o arquivo 'evento-exemplo.json' com curl ou Postman para testar."
