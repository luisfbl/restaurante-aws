import json
import os
import uuid
from datetime import datetime
from decimal import Decimal, InvalidOperation

import boto3
from botocore.exceptions import ClientError

LOCALSTACK_HOSTNAME = os.environ.get("LOCALSTACK_HOSTNAME", "localhost")
EDGE_PORT = os.environ.get("EDGE_PORT", "4566")

AWS_ENDPOINT_URL = os.environ.get(
    "AWS_ENDPOINT_URL", f"http://{LOCALSTACK_HOSTNAME}:{EDGE_PORT}"
)
AWS_REGION = os.environ.get("AWS_REGION", os.environ.get("AWS_DEFAULT_REGION", "us-east-1"))
DYNAMODB_TABLE = os.environ.get("DYNAMODB_TABLE", "Pedidos")
SQS_QUEUE_URL = os.environ.get("SQS_QUEUE_URL")

session = boto3.session.Session(region_name=AWS_REGION)
dynamodb = session.resource("dynamodb", endpoint_url=AWS_ENDPOINT_URL)
pedidos_table = dynamodb.Table(DYNAMODB_TABLE)
sqs_client = session.client("sqs", endpoint_url=AWS_ENDPOINT_URL)


def _build_response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }


def _validate_payload(payload):
    errors = []

    cliente = payload.get("cliente")
    if not isinstance(cliente, str) or not cliente.strip():
        errors.append("Campo 'cliente' é obrigatório e deve ser texto.")

    itens = payload.get("itens", [])
    if not isinstance(itens, list) or not itens:
        errors.append("Campo 'itens' deve ser uma lista com ao menos um item.")
    else:
        invalid_items = [item for item in itens if not isinstance(item, str) or not item.strip()]
        if invalid_items:
            errors.append("Todos os itens devem ser textos não vazios.")

    mesa = payload.get("mesa")
    try:
        mesa = int(mesa)
        if mesa <= 0:
            raise ValueError
    except (TypeError, ValueError):
        errors.append("Campo 'mesa' deve ser um número inteiro positivo.")

    return errors, cliente, itens, mesa


def lambda_handler(event, _context):
    if not event.get("body"):
        return _build_response(400, {"message": "Corpo da requisição inválido."})

    try:
        payload = json.loads(event["body"])
    except json.JSONDecodeError:
        return _build_response(400, {"message": "JSON inválido."})

    errors, cliente, itens, mesa = _validate_payload(payload)
    if errors:
        return _build_response(400, {"message": "Dados inválidos.", "erros": errors})

    pedido_id = str(uuid.uuid4())
    timestamp = datetime.utcnow().isoformat(timespec="seconds") + "Z"

    try:
        mesa_decimal = Decimal(mesa)
    except (InvalidOperation, TypeError):
        return _build_response(400, {"message": "Campo 'mesa' deve ser um número válido."})

    item = {
        "id": pedido_id,
        "cliente": cliente.strip(),
        "itens": [item.strip() for item in itens],
        "mesa": mesa_decimal,
        "status": "pendente",
        "criado_em": timestamp,
        "atualizado_em": timestamp,
    }

    try:
        pedidos_table.put_item(Item=item)
    except ClientError as error:
        print(f"Erro ao salvar pedido no DynamoDB: {error}")
        return _build_response(500, {"message": "Erro ao salvar pedido."})

    try:
        sqs_client.send_message(
            QueueUrl=SQS_QUEUE_URL,
            MessageBody=json.dumps({"pedido_id": pedido_id}),
        )
    except ClientError as error:
        print(f"Erro ao enviar mensagem para a fila SQS: {error}")
        return _build_response(500, {"message": "Erro ao enviar pedido para processamento."})

    return _build_response(
        201,
        {
            "message": "Pedido criado com sucesso",
            "pedido_id": pedido_id,
            "status": item["status"],
        },
    )
