const AWS = require("aws-sdk");
const docClient = new AWS.DynamoDB.DocumentClient();
const s3 = new AWS.S3();
const { gerarPDF } = require("../utils/gerarPDF");

exports.handler = async (event) => {
  for (const record of event.Records) {
    const { id } = JSON.parse(record.body);

    const pedido = await docClient.get({
      TableName: "Pedidos",
      Key: { id }
    }).promise();

    const pdfBuffer = gerarPDF(pedido.Item);

    await s3.putObject({
      Bucket: "comprovantes",
      Key: `${id}.pdf`,
      Body: pdfBuffer,
      ContentType: "application/pdf"
    }).promise();

    await docClient.update({
      TableName: "Pedidos",
      Key: { id },
      UpdateExpression: "set #s = :status",
      ExpressionAttributeNames: { "#s": "status" },
      ExpressionAttributeValues: { ":status": "PROCESSADO" }
    }).promise();
  }

  return { statusCode: 200 };
};
