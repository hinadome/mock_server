# GraphQL

## Summary (learn this first)

**GraphQL** is a query language and runtime for APIs. Clients usually talk to **one endpoint** and describe exactly which fields they want. The server returns JSON shaped like the query.

| Idea | Meaning |
|------|---------|
| Query | Read (`{ users { id name } }`) |
| Mutation | Write (`mutation { createUser(name: "Ada") { id } }`) |
| Subscription | Live stream over WebSocket |
| Schema | Shared contract of types and operations |
| Best for | Flexible clients, aggregating data, avoiding over/under-fetching |
| Not ideal for | Simple public caches (REST); binary RPC (gRPC); IoT pub/sub (MQTT) |

**Compared to others:** GraphQL typically rides on HTTP POST. Subscriptions on this server use **graphql-ws** on the same `/graphql` path (port `3000`), separate from the demo WebSocket server on `3001`.

## How it works

```
Query / Mutation (HTTP POST /graphql)
Client ---- JSON { query } ----> Yoga ----> JSON { data }

Subscription (WebSocket graphql-ws on /graphql)
Client <==== stream of { data } ==== Server
```

## On this server

| Item | Value |
|------|-------|
| HTTP port | `3000` |
| GraphiQL + HTTP API | `/graphql` |
| Path demo | `GET /graphql/demo` |
| Subscriptions | WebSocket `graphql-ws` on `/graphql` |
| Schema | [`mocks/graphql/schema.graphql`](../../mocks/graphql/schema.graphql) |
| Field fixtures | [`mocks/graphql/routes.yaml`](../../mocks/graphql/routes.yaml) |

## Built-in operations

**Queries:** `demo`, `hello(name)`, `user(id)`, `users`  
**Mutations:** `createUser`, `updateUser`, `deleteUser`, `publishOrder` (emits `orders.created`)  
**Subscriptions:** `countdown(from)`, `orderCreated`

## Try it — query & mutation

```bash
curl -X POST http://localhost:3000/graphql \
  -H 'Content-Type: application/json' \
  -d '{"query":"{ users { id name email } }"}'

curl -X POST http://localhost:3000/graphql \
  -H 'Content-Type: application/json' \
  -d '{"query":"{ user(id: \"42\") { id name } }"}'

curl -X POST http://localhost:3000/graphql \
  -H 'Content-Type: application/json' \
  -d '{"query":"mutation { createUser(name: \"Ada\", email: \"ada@example.com\") { id name } }"}'

curl -X POST http://localhost:3000/graphql \
  -H 'Content-Type: application/json' \
  -d '{"query":"mutation { updateUser(id: \"42\", name: \"Augusta\") { id name } }"}'

curl -X POST http://localhost:3000/graphql \
  -H 'Content-Type: application/json' \
  -d '{"query":"mutation { deleteUser(id: \"42\") { id deleted } }"}'
```

## Try it — subscriptions

1. Open http://localhost:3000/graphql  
2. Run:

```graphql
subscription { countdown(from: 3) }
```

3. In another GraphiQL tab:

```graphql
subscription { orderCreated { orderId status item } }
```

4. Trigger:

```graphql
mutation { publishOrder(item: "book") { orderId status item } }
```

Or from HTTP: `POST /http/orders` (also emits `orders.created`).

## Mock configuration

```graphql
# mocks/graphql/schema.graphql — define types & fields
type Query { users: [User!]! }
```

```yaml
# mocks/graphql/routes.yaml — fixture per field name
routes:
  - match: { operation: users }
    response:
      body:
        - { id: "1", name: Ada Lovelace }
```

Schema changes require a **server restart**. YAML field fixtures hot-reload.

## Common mistakes

- Missing `Content-Type: application/json`
- Putting mutations inside `query { }` — use `mutation { }`
- Expecting subscriptions over plain HTTP POST — need WebSocket / GraphiQL
- Editing `.graphql` schema and expecting hot-reload — restart required

## Learn more (references)

| Resource | Why read it |
|----------|-------------|
| [GraphQL.org — Learn](https://graphql.org/learn/) | Official path |
| [Queries and Mutations](https://graphql.org/learn/queries/) | Core operations |
| [Subscriptions](https://graphql.org/learn/subscriptions/) | Live updates |
| [Schemas and Types](https://graphql.org/learn/schema/) | Type system |
| [graphql-ws](https://github.com/enisdenjo/graphql-ws) | WS protocol used here |
| [GraphQL Spec](https://spec.graphql.org/) | Formal language |
| [How to GraphQL](https://www.howtographql.com/) | Free tutorial |
