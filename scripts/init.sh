#!/bin/bash

awslocal dynamodb create-table \
  --table-name Pedidos \
  --attribute-definitions AttributeName=id,AttributeType=S \
  --key-schema AttributeName=id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1

awslocal sqs create-queue \
  --queue-name pedidos \
  --region us-east-1

awslocal sns create-topic \
  --name PedidosConcluidos \
  --region us-east-1

awslocal s3 mb s3://comprovantes-pedidos --region us-east-1

cp /etc/localstack/init/ready.d/lambda/criar_pedido.py .
zip -q criar_pedido.zip criar_pedido.py
awslocal lambda create-function \
  --function-name criar-pedido \
  --runtime python3.11 \
  --handler criar_pedido.lambda_handler \
  --role arn:aws:iam::000000000000:role/lambda-role \
  --zip-file fileb:///tmp/criar_pedido.zip \
  --region us-east-1 \
  --timeout 60 \
  --environment "Variables={AWS_ENDPOINT_URL=http://localstack:4566}"

cp /etc/localstack/init/ready.d/lambda/processar_pedido.py .
zip -q processar_pedido.zip processar_pedido.py
awslocal lambda create-function \
  --function-name processar-pedido \
  --runtime python3.11 \
  --handler processar_pedido.lambda_handler \
  --role arn:aws:iam::000000000000:role/lambda-role \
  --zip-file fileb:///tmp/processar_pedido.zip \
  --region us-east-1 \
  --timeout 60 \
  --environment "Variables={AWS_ENDPOINT_URL=http://localstack:4566,S3_BUCKET_NAME=comprovantes-pedidos,SNS_TOPIC_ARN=arn:aws:sns:us-east-1:000000000000:PedidosConcluidos}"

API_ID=$(awslocal apigateway create-rest-api \
  --name pedidos-api \
  --region us-east-1 \
  --query 'id' \
  --output text)

RESOURCES=$(awslocal apigateway get-resources \
  --rest-api-id $API_ID \
  --region us-east-1 \
  --query 'items[0].id' \
  --output text)

RESOURCE_ID=$(awslocal apigateway create-resource \
  --rest-api-id $API_ID \
  --parent-id $RESOURCES \
  --path-part pedidos \
  --region us-east-1 \
  --query 'id' \
  --output text)

awslocal apigateway put-method \
  --rest-api-id $API_ID \
  --resource-id $RESOURCE_ID \
  --http-method POST \
  --authorization-type NONE \
  --region us-east-1

awslocal apigateway put-integration \
  --rest-api-id $API_ID \
  --resource-id $RESOURCE_ID \
  --http-method POST \
  --type AWS_PROXY \
  --integration-http-method POST \
  --uri arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:000000000000:function:criar-pedido/invocations \
  --region us-east-1

awslocal apigateway create-deployment \
  --rest-api-id $API_ID \
  --stage-name dev \
  --region us-east-1

QUEUE_ARN=$(awslocal sqs get-queue-attributes \
  --queue-url http://localstack:4566/000000000000/pedidos \
  --attribute-names QueueArn \
  --region us-east-1 \
  --query 'Attributes.QueueArn' \
  --output text)

awslocal lambda create-event-source-mapping \
  --event-source-arn $QUEUE_ARN \
  --function-name processar-pedido \
  --batch-size 1 \
  --region us-east-1
