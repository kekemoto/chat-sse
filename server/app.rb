require 'yaml'
require 'sinatra'
require 'redis'
require 'connection_pool'
require 'active_support'
require 'active_support/core_ext/object/blank'
require_relative './sse'

def new_redis_client
  Redis.new(host: 'redis')
end

def response_encode(data)
  JSON.generate data
end

def json(data)
  content_type 'application/json'
  body response_encode data
end

def redis_encode(data)
  YAML.dump data
end

def redis_decode(message)
  YAML.load message
end

def chat_message_encode(sender, text)
  redis_encode({sender: sender, text: text})
end

def chat_message_decode(redis_data)
  redis_decode redis_data
end

def chat_message_decode?(redis_data)
  chat_message = redis_decode redis_data
  return false unless chat_message.is_a?(Hash)
  chat_message.keys.to_set == Set[:sender, :text]
end

def chat_message_channel(receiver)
  "user/#{receiver}"
end

def chat_message_channel?(ch)
  /\Auser\//.match?(ch)
end

def user_attendance_encode(user, action)
  redis_encode({user: user, action: action})
end

def user_attendance_decode(redis_data)
  redis_decode redis_data
end

def user_attendance_channel
  "user_attendance"
end

def user_attendance_channel?(ch)
  "user_attendance" == ch
end

def logout_action(user)
  $redis.with do |c|
    c.srem(:users, user)
    c.publish(user_attendance_channel, user_attendance_encode(user, 'remove'))
  end
end

configure do
  set :close_id, 'a2120b03-5892-40c3-90d3-f65392ce7a3e'

  set :redis_timeout, 10
  set :redis_connection, 10
  $redis = ConnectionPool.new(size: settings.redis_connection, timeout: settings.redis_timeout){new_redis_client}
end

post '/login' do
  users = []
  user = params['user']
  $redis.with do |c|
    c.sadd(:users, user)
    c.publish(user_attendance_channel, user_attendance_encode(user, 'add'))
    users = c.smembers(:users)
  end
  json users
end

post '/send' do
  sender = params['sender']
  receiver = params['receiver']
  text = params['text']

  $redis.with do |c|
    c.publish(chat_message_channel(receiver), chat_message_encode(sender, text))
  end

  no_content
end

get '/receive/:user' do |user|
  no_content if last_event_id == settings.close_id

  r = new_redis_client
  sse do |out|
    out.on_close do
      $redis.with do |c|
        c.srem(:users, user)
        c.publish(user_attendance_channel, user_attendance_encode(user, 'remove'))
      end
      r.unsubscribe if r.subscribed?
    end

    channels = [
      chat_message_channel(user),
      user_attendance_channel,
    ]
    r.subscribe(*channels) do |on|
      on.message do |ch, redis_data|
        if chat_message_channel?(ch)
          out.write response_encode chat_message_decode redis_data
          next
        end

        if user_attendance_channel?(ch)
          event = user_attendance_decode redis_data
          id = nil

          if event['action'] == 'remove' && event['user'] == user
            r.unsubscribe if r.subscribed?
            id = setting.close_id
          end

          out.write event: user_attendance_channel, data: response_encode(event), id: id
          next
        end

        raise "It will not run. ...maybe."
      end
    end
  end
end

get '*' do
  call env.merge("PATH_INFO" => '/index.html')
end
