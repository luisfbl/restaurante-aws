exports.gerarPDF = (pedido) => {
  const content = `Pedido: ${pedido.id}\nCliente: ${pedido.cliente}\nItens: ${pedido.itens.join(", ")}\nMesa: ${pedido.mesa}`;
  return Buffer.from(content); // Simulação de PDF
};
