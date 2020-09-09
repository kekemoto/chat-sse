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
```

### start

```
# Start server. If the file is changed, it will restart automatically.
docker-compose up -d

# Build client. If the file is changed, it will restart automatically.
npm run watch
```

Try to access [http://localhost/](http://localhost/)

## stop

```
docker-compose stop
```
