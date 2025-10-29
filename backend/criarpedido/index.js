const { v4: uuidv4 } = require("uuid");
const AWS = require("aws-sdk");
const docClient = new AWS.DynamoDB.DocumentClient();
const sqs = new AWS.SQS();

exports.handler = async (event) => {
  const body = JSON.parse(event.body);
  const id = uuidv4();

  const pedido = {
    id,
    cliente: body.cliente,
    itens: body.itens,
    mesa: body.mesa,
    status: "PENDENTE"
  };

  await docClient.put({
    TableName: "Pedidos",
    Item: pedido
  }).promise();

  await sqs.sendMessage({
    QueueUrl: process.env.SQS_URL,
    MessageBody: JSON.stringify({ id })
  }).promise();

  return {
    statusCode: 201,
    body: JSON.stringify({ message: "Pedido criado", id })
  };
};
