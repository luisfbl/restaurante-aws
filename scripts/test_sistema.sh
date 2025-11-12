#!/bin/bash

export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1
ENDPOINT_URL=http://localhost:4566

API_ID=$(aws --endpoint-url=$ENDPOINT_URL apigateway get-rest-apis --query 'items[0].id' --output text --region us-east-1)
echo "   API ID: $API_ID"
echo ""

RESPONSE=$(curl -s -X POST "http://localhost:4566/restapis/$API_ID/dev/_user_request_/pedidos" \
  -H "Content-Type: application/json" \
  -d '{
    "cliente": "Maria Silva",
    "itens": ["Hambúrguer", "Batata Frita", "Coca-Cola"],
    "mesa": 10
  }')

echo "   Resposta: $RESPONSE"
PEDIDO_ID=$(echo $RESPONSE | grep -o '"pedido_id": "[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
echo "   Pedido ID: $PEDIDO_ID"

echo "Aguardando processamento do pedido..."
sleep 8
echo ""

aws --endpoint-url=$ENDPOINT_URL dynamodb get-item \
  --table-name Pedidos \
  --key "{\"id\":{\"S\":\"$PEDIDO_ID\"}}" \
  --query 'Item.{ID:id.S,Cliente:cliente.S,Status:status.S,Mesa:mesa.N,ComprovanteURL:comprovante_url.S}' \
  --output table \
  --region us-east-1
echo ""

aws --endpoint-url=$ENDPOINT_URL sqs receive-message \
  --queue-url http://localstack:4566/000000000000/pedidos \
  --max-number-of-messages 1 \
  --region us-east-1
echo ""

aws --endpoint-url=$ENDPOINT_URL s3 ls s3://comprovantes-pedidos/comprovantes/ \
  --region us-east-1 | grep "$PEDIDO_ID" || echo "   Arquivo ainda não disponível."
echo ""

aws --endpoint-url=$ENDPOINT_URL s3api head-object \
  --bucket comprovantes-pedidos \
  --key "comprovantes/$PEDIDO_ID.pdf" \
  --region us-east-1
echo ""

aws --endpoint-url=$ENDPOINT_URL sns list-topics \
  --query 'Topics[*].TopicArn' \
  --output table \
  --region us-east-1
echo ""

TOPIC_ARN="arn:aws:sns:us-east-1:000000000000:PedidosConcluidos"
aws --endpoint-url=$ENDPOINT_URL sns list-subscriptions-by-topic \
  --topic-arn $TOPIC_ARN \
  --query 'Subscriptions[*].{Protocol:Protocol,Endpoint:Endpoint,SubscriptionArn:SubscriptionArn}' \
  --output table \
  --region us-east-1
