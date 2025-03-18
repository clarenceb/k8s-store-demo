'use strict'

module.exports = async function (fastify, opts) {
  fastify.post('/', async function (request, reply) {
    const msg = request.body;

    try {
      // Attempt to send the message
      await fastify.sendMessage(Buffer.from(JSON.stringify(msg)));
      // If successful, return 201 Created
      reply.code(201).send({ message: 'Order submitted successfully' });
    } catch (error) {
      // Log the error for debugging purposes
      fastify.log.error(error);

      // Return a 500 Internal Server Error with a meaningful message
      reply.code(500).send({
        error: 'Failed to process order',
        details: error.message || 'An error occurred while sending the message',
      });
    }
  });  

  fastify.get('/health', async function (request, reply) {
    const appVersion = process.env.APP_VERSION || '0.1.0'
    return { status: 'ok', version: appVersion }
  })

  fastify.get('/hugs', async function (request, reply) {
    return { hugs: fastify.someSupport() }
  })
}
