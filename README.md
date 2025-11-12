# Sistema de Pedidos de Restaurante (Serverless)

Ambiente completo para simular um fluxo de pedidos de restaurante usando arquitetura serverless (API Gateway + Lambda + DynamoDB + SQS + S3 + SNS) executada localmente com LocalStack.

## Arquitetura

- **API Gateway** (`POST /pedidos`) recebe pedidos HTTP.
- **Lambda criar-pedido** valida payload, grava na tabela `Pedidos` (DynamoDB) e envia o `pedido_id` para a fila `pedidos` (SQS).
- **Lambda processar-pedido** consome a fila, busca o pedido no DynamoDB, gera um comprovante em PDF e salva em `s3://comprovantes-pedidos/comprovantes/<id>.pdf`, atualiza o status para `concluido` e dispara notificação no tópico `PedidosConcluidos` (SNS).

## Pré-requisitos

- Docker + Docker Compose.
- Python 3.9+.
- AWS CLI configurada com as credenciais do LocalStack (`test/test`).

## Subindo o ambiente

```bash
docker compose up -d

# Aguarde os logs indicarem "Ready".
docker compose logs -f localstack
```

`scripts/init.sh` é executado automaticamente pelo LocalStack e cria todos os serviços, empacota e publica as Lambdas com as variáveis necessárias.

## Teste end-to-end

```bash
./scripts/test_sistema.sh
```

O script:
1. Descobre o API ID.
2. Faz um `POST /pedidos`.
3. Aguarda o processamento assíncrono.
4. Verifica o item no DynamoDB.
5. Confere a fila SQS (deve estar vazia).
6. Lista o PDF no S3 e faz um `head-object`.
7. Lista tópicos e inscrições do SNS.

## Criando pedido manualmente

```bash
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1
API_ID=$(aws --endpoint-url=http://localhost:4566 apigateway get-rest-apis --query 'items[0].id' --output text)

curl -X POST "http://localhost:4566/restapis/$API_ID/dev/_user_request_/pedidos" \
  -H "Content-Type: application/json" \
  -d '{"cliente":"João","itens":["Pizza","Refrigerante"],"mesa":5}'
```

## Baixando o comprovante em PDF

Se a Lambda retornar `s3://comprovantes-pedidos/comprovantes/<ID>.pdf`, use:

```bash
aws --endpoint-url=http://localhost:4566 s3 cp \
  s3://comprovantes-pedidos/comprovantes/<ID>.pdf ./comprovante.pdf
open ./comprovante.pdf
```

## Estrutura

```
docker-compose.yml
lambda/
  criar_pedido.py
  processar_pedido.py
  reportlab_lib/           # libs empacotadas para a Lambda de processamento
scripts/
  init.sh                  # provisiona recursos no LocalStack
  test_sistema.sh          # teste e2e
```

Pronto! Com isso você consegue iniciar o fluxo completo localmente e gerar comprovantes PDF reais usando ReportLab dentro da Lambda.
