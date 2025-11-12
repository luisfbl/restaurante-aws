import json
import os
from datetime import datetime
from decimal import Decimal
from io import BytesIO

import boto3
from botocore.exceptions import ClientError

LOCALSTACK_HOSTNAME = os.environ.get("LOCALSTACK_HOSTNAME", "localhost")
EDGE_PORT = os.environ.get("EDGE_PORT", "4566")
ENDPOINT_URL = os.environ.get(
    "AWS_ENDPOINT_URL", f"http://{LOCALSTACK_HOSTNAME}:{EDGE_PORT}"
)
AWS_REGION = os.environ.get("AWS_REGION", os.environ.get("AWS_DEFAULT_REGION", "us-east-1"))
BUCKET_NAME = os.environ.get("S3_BUCKET_NAME", "comprovantes-pedidos")
SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN")
DYNAMODB_TABLE = os.environ.get("DYNAMODB_TABLE", "Pedidos")

session = boto3.session.Session(region_name=AWS_REGION)
s3_client = session.client("s3", endpoint_url=ENDPOINT_URL)
sns_client = session.client("sns", endpoint_url=ENDPOINT_URL)
dynamodb = session.resource("dynamodb", endpoint_url=ENDPOINT_URL)
pedidos_table = dynamodb.Table(DYNAMODB_TABLE)


def _escape_pdf_text(value):
    text = str(value)
    return text.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")


def _build_pdf_document(content_bytes):
    pdf = bytearray(b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")
    objects = []

    objects.append(b"1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n")
    objects.append(b"2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj\n")
    objects.append(
        b"3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
        b"/Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >> endobj\n"
    )

    stream_header = f"<< /Length {len(content_bytes)} >>\nstream\n".encode("utf-8")
    stream_footer = b"\nendstream\n"
    objects.append(b"4 0 obj\n" + stream_header + content_bytes + stream_footer + b"endobj\n")

    objects.append(
        b"5 0 obj << /Type /Font /Subtype /Type1 /Name /F1 /BaseFont /Helvetica >> endobj\n"
    )

    offsets = []
    for obj in objects:
        offsets.append(len(pdf))
        pdf.extend(obj)

    xref_pos = len(pdf)
    total_objs = len(objects) + 1
    pdf.extend(f"xref\n0 {total_objs}\n".encode("utf-8"))
    pdf.extend(b"0000000000 65535 f \n")
    for offset in offsets:
        pdf.extend(f"{offset:010d} 00000 n \n".encode("utf-8"))

    pdf.extend(
        f"trailer << /Size {total_objs} /Root 1 0 R >>\nstartxref\n{xref_pos}\n%%EOF".encode(
            "utf-8"
        )
    )
    return bytes(pdf)


def generate_pdf(data):
    try:
        lines = ["BT", "/F1 18 Tf", "50 780 Td (Comprovante de Pedido) Tj"]

        cliente = data.get("cliente", "N/A")
        mesa = data.get("mesa", "N/A")
        pedido_id = data.get("id_pedido", "N/A")

        lines.append(
            "0 -30 Td /F1 12 Tf ({}) Tj".format(_escape_pdf_text(f"ID: {pedido_id}"))
        )
        lines.append("0 -18 Td ({}) Tj".format(_escape_pdf_text(f"Cliente: {cliente}")))
        lines.append("0 -18 Td ({}) Tj".format(_escape_pdf_text(f"Mesa: {mesa}")))
        lines.append("0 -24 Td (Itens:) Tj")

        for item in data.get("itens", []):
            lines.append("0 -18 Td ({}) Tj".format(_escape_pdf_text(f"- {item}")))

        lines.append("ET")
        content_bytes = "\n".join(lines).encode("utf-8")
        pdf_bytes = _build_pdf_document(content_bytes)
        return BytesIO(pdf_bytes)
    except Exception as err:
        print(f"Erro ao gerar PDF: {err}")
        return None


def _fetch_order(pedido_id):
    try:
        response = pedidos_table.get_item(Key={"id": pedido_id})
        return response.get("Item")
    except ClientError as error:
        print(f"Erro ao buscar pedido {pedido_id}: {error}")
        return None


def _update_status(pedido_id, status, comprovante_url=None):
    timestamp = datetime.utcnow().isoformat(timespec="seconds") + "Z"
    expression = ["#status = :status", "#updated_at = :updated"]
    names = {"#status": "status", "#updated_at": "atualizado_em"}
    values = {":status": status, ":updated": timestamp}

    if comprovante_url is not None:
        expression.append("#comprovante_url = :comprovante")
        names["#comprovante_url"] = "comprovante_url"
        values[":comprovante"] = comprovante_url

    update_expression = "SET " + ", ".join(expression)

    try:
        pedidos_table.update_item(
            Key={"id": pedido_id},
            UpdateExpression=update_expression,
            ExpressionAttributeNames=names,
            ExpressionAttributeValues=values,
        )
    except ClientError as error:
        print(f"Erro ao atualizar pedido {pedido_id}: {error}")


def handler(event, _context):
    for record in event["Records"]:
        try:
            payload = json.loads(record["body"])
            pedido_id = payload.get("pedido_id") or payload.get("id")
            if not pedido_id:
                print("Mensagem sem 'pedido_id'. Ignorando.")
                continue

            pedido = _fetch_order(pedido_id)
            if not pedido:
                print(f"Pedido {pedido_id} não encontrado.")
                continue

            itens = pedido.get("itens", [])
            mesa = pedido.get("mesa")
            if isinstance(mesa, Decimal):
                mesa = int(mesa)

            _update_status(pedido_id, "processando")
            pdf_buffer = generate_pdf(
                {
                    "id_pedido": pedido_id,
                    "cliente": pedido.get("cliente", "N/A"),
                    "mesa": mesa,
                    "itens": itens,
                }
            )

            if not pdf_buffer:
                _update_status(pedido_id, "erro")
                continue

            object_key = f"comprovantes/{pedido_id}.pdf"
            s3_client.put_object(
                Bucket=BUCKET_NAME,
                Key=object_key,
                Body=pdf_buffer.getvalue(),
                ContentType="application/pdf",
            )
            comprovante_url = f"s3://{BUCKET_NAME}/{object_key}"
            print(f"PDF salvo em {comprovante_url}")

            _update_status(pedido_id, "concluido", comprovante_url)

            sns_client.publish(
                TopicArn=SNS_TOPIC_ARN,
                Message=f"Novo pedido concluído: {pedido_id}",
                Subject="Pedido Pronto!",
            )

        except Exception as error:
            print(f"Erro ao processar registro: {error}")

    return {"statusCode": 200, "body": json.dumps("Processamento concluído.")}
