import json
import boto3
import os
from io import BytesIO
from reportlab.pdfgen import canvas
from reportlab.lib.pagesizes import A4

# Configuração do cliente boto3 para S3 e SNS apontando para o LocalStack
LOCALSTACK_HOSTNAME = os.environ.get('LOCALSTACK_HOSTNAME', 'localhost')
EDGE_PORT = os.environ.get('EDGE_PORT', '4566')
ENDPOINT_URL = f"http://{LOCALSTACK_HOSTNAME}:{EDGE_PORT}"

s3_client = boto3.client('s3', endpoint_url=ENDPOINT_URL)
sns_client = boto3.client('sns', endpoint_url=ENDPOINT_URL)

BUCKET_NAME = os.environ.get('S3_BUCKET_NAME', 'comprovantes-pedidos')
# ARN do tópico SNS para notificações
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN')

def generate_pdf(data):
    """Gera um PDF simples em memória com os dados da mensagem."""
    try:
        buffer = BytesIO()

        p = canvas.Canvas(buffer, pagesize=A4)
        width, height = A4 

        p.setFont("Helvetica-Bold", 18)
        p.drawString(100, height - 100, "Comprovante de Pedido")
        
        p.setFont("Helvetica", 12)
        p.drawString(100, height - 130, f"ID do Pedido: {data.get('id_pedido', 'N/A')}")
        p.drawString(100, height - 150, f"Cliente: {data.get('cliente', 'N/A')}")
        p.drawString(100, height - 170, f"Mesa: {data.get('mesa', 'N/A')}")
        
        p.setFont("Helvetica-Bold", 12)
        p.drawString(100, height - 200, "Itens do Pedido:")
        p.setFont("Helvetica", 10)
        
        itens = data.get('itens', [])
        for i, item in enumerate(itens):
            p.drawString(120, height - 220 - (i * 20), f"- {item}")

        p.showPage()
        p.save()

        buffer.seek(0)
        return buffer
        
    except Exception as e:
        print(f"Erro ao gerar PDF: {e}")
        return None

def handler(event, context):
    """Função principal da Lambda."""
    
    print("Evento SQS recebido...")
    
    for record in event['Records']:
        try:
            
            message_body_str = record['body']
            data = json.loads(message_body_str)
            print(f"Processando dados: {data}")


            pdf_buffer = generate_pdf(data)
            
            if pdf_buffer:
                file_name = f"relatorio-{data.get('id_pedido', 'default')}.pdf"
                
                s3_client.put_object(
                    Bucket=BUCKET_NAME,
                    Key=file_name,
                    Body=pdf_buffer,
                    ContentType='application/pdf'
                )
                print(f"Sucesso! PDF salvo em s3://{BUCKET_NAME}/{file_name}")

                if SNS_TOPIC_ARN:
                    sns_subject = "Pedido Pronto!"
                    sns_message = f"Novo pedido concluído: {data.get('id_pedido', 'N/A')}"
                    
                    sns_client.publish(
                        TopicArn=SNS_TOPIC_ARN,
                        Message=sns_message,
                        Subject=sns_subject
                    )
                    print(f"Notificação de pedido concluído enviada para o tópico {SNS_TOPIC_ARN}")
                else:
                    print("Variável de ambiente SNS_TOPIC_ARN não configurada. Pulando notificação.")
            else:
                print("Falha ao gerar o buffer do PDF.")

        except Exception as e:
            print(f"Erro ao processar registro: {e}")
            
    return {
        'statusCode': 200,
        'body': json.dumps('Processamento concluído.')
    }