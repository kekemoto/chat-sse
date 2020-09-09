import React, {Fragment, useState, useEffect, useRef, useReducer} from 'react'
import ReactDOM from 'react-dom'
import {List, Map} from 'immutable'

function App(){
	const [page, setPage] = useState('Login')
	const [user, setUser] = useState(null)
	const [talkUser, setTalkUser] = useState(null)
	const [messageBox, messageBoxAction] = useReducer(messageBoxReducer, Map())
	const [users, usersAction] = useReducer(usersReducer, List())
	const eventSource = useRef(null)

	function logout(){
		usersAction({type: 'remove', user})
		messageBoxAction({type: 'init'})
		setUser(null)
	}

	subscribe(eventSource, user, {
		message: (event) => {
			let message = JSON.parse(event.data)
			message.is_read = false
			messageBoxAction({type: 'receive', message})
		},
		user_attendance: (event) => {
			let data = JSON.parse(event.data)
			switch(data.action){
				case 'add':
					usersAction({type: 'add', user: data.user})
					return
				case 'remove':
					usersAction({type: 'remove', user: data.user})
					return
				default:
					throw new Error(event.data)
			}
		},
		error: reportError,
	})

	const talkUserOnline = users.includes(talkUser)

	const PAGES = {
		Login: <Login {...{setPage, setUser, logout}} />,
		UserList: <UserList {...{setPage, user, users, usersAction, setTalkUser, messageBox}} />,
		Chat: <Chat {...{setPage, user, talkUser, messageBoxAction, messages: messageBox.get(talkUser, List()), online: talkUserOnline}} />,
	}

	return PAGES[page]
}

function messageBoxReducer(state, action){
	let messages = null
	switch(action.type){
		case 'init':
			return Map()
		case 'receive':
			let sender = action.message.sender
			messages = state.get(sender, List())
			return state.set(sender, messages.push(action.message))
		case 'send':
			let receiver = action.message.receiver
			messages = state.get(receiver, List())
			return state.set(receiver, messages.push(action.message))
		case 'read':
			messages = state.get(action.user, List()).map(m => {
				m.is_read = true
				return m
			})
			return state.set(action.user, messages)
		default:
			throw new Error(`Action type ${action.type} is not implemented.`)
	}
}

function usersReducer(state, action){
	switch(action.type){
		case 'set':
			return action.users
		case 'add':
			return state.push(action.user)
		case 'remove':
			return state.filter(user => user != action.user)
		default:
			throw new Error(`Action type ${action.type} is not implemented.`)
	}
}

function Login({setPage, setUser, logout}){
	const [name, setName] = useState('')

	useEffect(logout, [])

	function onChange(event){
		setName(event.target.value)
	}

	function onSubmit(event){
		event.preventDefault();
		if(name.length === 0){return false}

		setUser(name)
		setPage('UserList')
	}

	return <Fragment>
		<form onSubmit={onSubmit} className='login'>
			<input type='text' value={name} onChange={onChange}  placeholder='Name' autoFocus/>
			<input type='submit' value='Login' />
		</form>
	</Fragment>
}

function UserList({setPage, user, users, usersAction, setTalkUser, messageBox}){
	useEffect(() => {
		post('/login', {user})
		.then(data => usersAction({type: 'set', users: List(data)}))
		.catch(reportError)
	}, [])

	function onClick(user){
		setTalkUser(user)
		setPage('Chat')
	}

	const list = users.filter((value) => value !== user).map((user) => {
		let unread_size = messageBox.get(user, List()).filter(m => !m.is_read).size
		return {user, unread_size}
	})

	return <Fragment>
		<Header title="User List" onBack={() => setPage('Login')} />
		<div className="user-list">
			{list.size === 0 && "Nobody is here."}
			<ul>
				{list.map(item =>
					<li key={item.user} onClick={() => onClick(item.user)} className="user-list-item">
						<div className="user-list-name">{item.user}</div>
						<div className="user-list-unread">{item.unread_size}</div>
					</li>
				)}
			</ul>
		</div>
	</Fragment>
}

function Chat({setPage, user, talkUser, messages, messageBoxAction, online}){
	const [text, setText] = useState('')

	useEffect(() => {
		messageBoxAction({type: 'read', user: talkUser})
	}, [messages])

	useEffect(() => {
		if(!online){setPage('UserList')}
	}, [online])

	function onChange(event){
		setText(event.target.value)
	}

	function onSubmit(event){
		event.preventDefault();
		if(text.length === 0){return false}

		const message = {sender: user, receiver: talkUser, text, is_read: true}
		post('/send', message)
		.then(() => {
			setText('')
			messageBoxAction({type: 'send', message})
		})
		.catch(reportError)
	}

	return <Fragment>
		<Header onBack={() => setPage('UserList')} title={talkUser}/>
		<div className='chat'>
			<div className="chat-list">
				{messages.map((m) => <div key={message_key(m)} className={`chat-message ${m.sender === user ? 'chat-self' : 'chat-other'}`}>{m.text}</div>)}
			</div>
			<form onSubmit={onSubmit} className='chat-sender'>
				<input type='text' value={text} onChange={onChange}  placeholder='message...' className='chat-sender-text' autoFocus />
				<input type='submit' value='Send' className='chat-sender-submit' />
			</form>
		</div>
	</Fragment>
}

function Header({onBack, title}){
	return <div className="header">
		<div onClick={onBack} className="header-back">
			<i className="fas fa-arrow-left"></i>
		</div>
		<div className="header-title">
			{title}
		</div>
	</div>
}

function subscribe(ref, user, listeners){
	useEffect(() => {
		if(user !== null){
			let e = new EventSource(`receive/${user}`)

			for(let key in listeners){
				e.addEventListener(key, listeners[key], false)
			}

			ref.current = e

		} else {
			if(ref.current !== null){
				ref.current.close()
			}
		}
	}, [user])
}

function message_key(m){
	return `${m.sender}${m.text}`
}

function post(url, body){
	return fetchCheckOk('POST', url, formData(body)).then(parse_response)
}
function get(url, body){
	return fetchCheckOk('GET', url, formData(body)).then(parse_response)
}
function fetchCheckOk(method, url, body){
	return fetch(url, {method, body}).then(response => {
		if(!response.ok){
			throw new Error(response.status)
		}
		return response
	})
}
function parse_response(res){
	return res.json()
}

function reportError(err){
	console.error(err.message)
	throw err
}

function formData(obj){
	let f = new FormData()
	for(let key in obj){
		f.append(key, obj[key])
	}
	return f
}

window.addEventListener('DOMContentLoaded', (event) => {
	ReactDOM.render(<App />, document.getElementById("app"))
})
