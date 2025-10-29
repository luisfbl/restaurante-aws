# 🍽️ Sistema de Pedidos de Restaurante (Serverless)

Este projeto simula um sistema de gerenciamento de pedidos de restaurante com arquitetura **Serverless**, utilizando **AWS Lambda**, **DynamoDB**, **SQS**, **S3** e **API Gateway**, totalmente emulado localmente com o **LocalStack**.

---

## 📦 Funcionalidades

1. **Recebimento de pedidos via API HTTP (POST)**
2. **Validação e armazenamento dos pedidos no DynamoDB**
3. **Envio de mensagens para uma fila SQS**
4. **Processamento assíncrono dos pedidos (Lambda)**
5. **Geração de comprovantes em PDF (simulado) e envio ao S3**

---

## 🧱 Arquitetura do Sistema

```text
Cliente → API Gateway → Lambda (Criar Pedido) 
        → DynamoDB
        → SQS → Lambda (Processar Pedido) 
                      → S3 (comprovantes)

## 🚀 Como executar localmente

1. Clone o repositório

    git clone https://github.com/seu-usuario/restauranteFabio.git
    cd restauranteFabio

2. Instale as dependências (Node.js)

    npm install

3. Suba o ambiente com Docker + LocalStack

    docker-compose up -d

4. Configure os serviços da AWS no LocalStack

    chmod +x scripts/setup.sh
    bash ./scripts/setup.sh
