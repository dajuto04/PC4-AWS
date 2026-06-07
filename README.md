# PC4: Consolidación de conocimientos de Arquitecturas Basadas en Eventos

## Objetivo

Este proyecto tiene como objetivo consolidar los conocimientos adquiridos a lo largo del módulo de Arquitecturas Basadas en Eventos (EDA), aplicándolos de forma práctica mediante el diseño e implementación de una arquitectura orientada a eventos con una aplicación realista.

El proyecto se realizará en grupos de 3–4 alumnos, con una dedicación total estimada de 10–15 horas por grupo (aproximadamente 3–4 horas por alumno).

El foco del proyecto no es únicamente que la arquitectura funcione, sino demostrar criterio de diseño, comprensión de los patrones event-driven y la capacidad de justificar decisiones técnicas.

## Contexto general del proyecto

Los sistemas modernos rara vez son monolíticos o puramente síncronos. En su lugar, se basan en:

- eventos
- procesamiento asíncrono
- streaming
- desacoplamiento
- estado derivado

En este proyecto deberéis construir una arquitectura basada en eventos que procese información de forma asíncrona y/o en streaming, mantenga estado derivado y permita extensión y escalado.

## Requisitos generales

### Tecnológicos

El proyecto debe poder resolverse usando una de estas dos opciones (a elegir por el grupo):

#### Opción A – Cloud (AWS)

- SNS / SQS
- EventBridge
- Lambda
- DynamoDB / DynamoDB Streams
- (Opcional) Kinesis / MSK si la cuenta lo permite

#### Opción B – Open Source

- Kafka / Pulsar
- Consumers / Producers
- Procesamiento (Kafka Streams, Flink, Spark Streaming, etc.)
- Almacenamiento de datos (Redis, PostgreSQL, MongoDB, etc.)

No es obligatorio usar todas las tecnologías, pero sí justificar claramente las elecciones.

## Caso de uso (a elegir o proponer)

Cada grupo debe implementar uno de los siguientes casos de uso, o proponer uno equivalente (previa validación):

### Ejemplos de casos de uso

- Plataforma de eventos de usuarios (clicks, pagos, acciones)
- Procesamiento de eventos IoT (sensores, métricas, alertas)
- Sistema de pedidos (creación, validación, facturación, notificación)
- Sistema de monitorización / métricas en tiempo casi real

El sistema debe generar eventos continuamente (simulados o reales).

## Requisitos funcionales mínimos

### 1. Generación de eventos

- Simular una fuente de eventos continua (script, API, productor, etc.)
- Los eventos deben contener:
  - identificador
  - timestamp
  - algún atributo de negocio (usuario, sensor, pedido, etc.)

### 2. Ingesta y canalización de eventos

- Usar un canal de eventos (topic, stream, queue, bus)
- Separar claramente:
  - productores
  - consumidores
- Justificar el tipo de comunicación:
  - pub/sub
  - colas
  - streaming

### 3. Procesamiento asíncrono / streaming

- Procesar eventos en near-real-time
- Demostrar comprensión de:
  - orden
  - concurrencia
  - retries
  - idempotencia (aunque sea parcial)

### 4. Estado y agregados

El sistema debe mantener estado derivado a partir de eventos, por ejemplo:

- contadores
- sumas
- último valor conocido
- agregados por ventana temporal (opcional)

Este estado:

- no debe recalcularse desde cero
- debe actualizarse incrementalmente

### 5. Persistencia

- Almacenar eventos individuales (opcional pero recomendado)
- Almacenar estado agregado
- Justificar el modelo de datos elegido

### 6. Manejo de errores

Demostrar qué ocurre cuando un evento falla:

- retries
- DLQ
- reintentos

Explicar las implicaciones.

## Requisitos no funcionales

- Arquitectura desacoplada
- Escalado razonable
- Uso responsable de recursos (especialmente en AWS Free Tier)

## Entregables

### 1. README.md

Debe incluir:

- descripción del caso de uso
- diagrama de arquitectura (alto nivel, más detallado en punto 3)
- explicación del flujo de eventos
- decisiones técnicas

### 2. Código fuente

- scripts de generación de eventos
- consumidores / lambdas
- infraestructura (si aplica)

### 3. Diagrama de arquitectura

- estilo AWS oficial o equivalente
- claro y legible

### 4. Opcional

- Capturas o logs demostrando el sistema en ejecución
