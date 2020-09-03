# Chat-SSE

chat by server-sent-events, sinatra, puma, redis

## Make developmenet enviroment

### requirement

- docker
- docker-compose
- npm

### setup

```
git clone https://github.com/kekemoto/chat-sse.git
cd chat-sse
docker-compose build
npm run build
```

### start server

```
docker-compose up -d
```

Try to access [http://localhost/](http://localhost/)

## stop server

```
docker-compose stop
```
