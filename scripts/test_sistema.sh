#!/bin/bash
set -e

export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1
ENDPOINT_URL=http://localhost:4566

echo "=== Teste do Sistema de Pedidos ==="
echo ""

# Aguardar Lambda estar ativa
echo "1. Verificando estado das Lambdas..."
aws --endpoint-url=$ENDPOINT_URL lambda wait function-active-v2 --function-name criar-pedido --region us-east-1 2>/dev/null || true
aws --endpoint-url=$ENDPOINT_URL lambda wait function-active-v2 --function-name processar-pedido --region us-east-1 2>/dev/null || true
echo "   Lambdas prontas!"
echo ""

# Obter API Gateway ID
echo "2. Obtendo API Gateway..."
API_ID=$(aws --endpoint-url=$ENDPOINT_URL apigateway get-rest-apis --query 'items[0].id' --output text --region us-east-1)
echo "   API ID: $API_ID"
echo ""

echo "3. Criando pedido via API Gateway..."
RESPONSE=$(curl -s -X POST "http://localhost:4566/restapis/$API_ID/dev/_user_request_/pedidos" \
  -H "Content-Type: application/json" \
  -d '{
    "cliente": "Maria Silva",
    "itens": ["Hambúrguer", "Batata Frita", "Coca-Cola"],
    "mesa": 10
  }')

echo "   Resposta: $RESPONSE"
echo ""

# Extrair pedido ID
PEDIDO_ID=$(echo $RESPONSE | grep -o '"pedido_id": "[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')

if [ -z "$PEDIDO_ID" ] || [ "$PEDIDO_ID" == "null" ]; then
  echo "   ERRO: Pedido ID não foi retornado!"
  echo "   Resposta completa: $RESPONSE"
  exit 1
fi

echo "   Pedido ID: $PEDIDO_ID"
echo ""

echo "4. Aguardando processamento do pedido (8 segundos)..."
sleep 8
echo ""

echo "5. Consultando pedido no DynamoDB..."
aws --endpoint-url=$ENDPOINT_URL dynamodb get-item \
  --table-name Pedidos \
  --key "{\"id\":{\"S\":\"$PEDIDO_ID\"}}" \
  --query 'Item.{ID:id.S,Cliente:cliente.S,Status:status.S,Mesa:mesa.N,ComprovanteURL:comprovante_url.S}' \
  --output table \
  --region us-east-1
echo ""

echo "6. Verificando mensagens na fila SQS..."
aws --endpoint-url=$ENDPOINT_URL sqs receive-message \
  --queue-url http://localhost:4566/000000000000/pedidos \
  --max-number-of-messages 1 \
  --region us-east-1
echo ""

echo "7. Listando comprovantes no S3..."
aws --endpoint-url=$ENDPOINT_URL s3 ls s3://comprovantes-pedidos/comprovantes/ \
  --region us-east-1 | grep "$PEDIDO_ID" || echo "   Arquivo ainda não disponível."
echo ""

echo "8. Verificando metadados do comprovante..."
aws --endpoint-url=$ENDPOINT_URL s3api head-object \
  --bucket comprovantes-pedidos \
  --key "comprovantes/$PEDIDO_ID.pdf" \
  --region us-east-1 2>/dev/null || echo "   Comprovante ainda não foi gerado."
echo ""

echo "9. Listando tópicos SNS..."
aws --endpoint-url=$ENDPOINT_URL sns list-topics \
  --query 'Topics[*].TopicArn' \
  --output table \
  --region us-east-1
echo ""

echo "10. Listando inscrições no tópico PedidosConcluidos..."
TOPIC_ARN="arn:aws:sns:us-east-1:000000000000:PedidosConcluidos"
aws --endpoint-url=$ENDPOINT_URL sns list-subscriptions-by-topic \
  --topic-arn $TOPIC_ARN \
  --query 'Subscriptions[*].{Protocol:Protocol,Endpoint:Endpoint,SubscriptionArn:SubscriptionArn}' \
  --output table \
  --region us-east-1

echo ""
echo "=== Teste concluído! ==="
