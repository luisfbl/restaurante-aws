Sistema de Pedidos de Restaurante (Serverless)
Um restaurante precisa de um sistema para gerenciar pedidos online, onde:
1. Clientes fazem pedidos via API HTTP.
2. Pedidos são validados e armazenados em um banco de dados NoSQL.
3. A cozinha recebe os pedidos via filas de mensagens.
4. O sistema gera comprovantes em PDF e os armazena em S3.
5. Tudo é executado em um ambiente local com LocalStack.