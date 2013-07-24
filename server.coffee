# Imports
express = require 'express'
http    = require 'http'           # http.createServer
path    = require 'path'           # path.join
qs      = require 'querystring'

Users           = require './users'
PublicClient    = require './publicClient'

# Config of the app
config = require './config'
PORT = config.port
APP = config.app
PROD_MODE = config.prod

# Constants
ESSAY_TYPE = 'https://tent.io/types/essay/v0#'

# additional server side information about an entity / user
sessions = {}

emptyFlash = ->
    error: []
    success: []

###
# Creation of the server, using expressjs.
###
app = new express()
app.configure () ->
    app.set 'port', PORT

    app.set 'views', __dirname + '/views'
    app.set 'view engine', 'jade'
    app.use express.static path.join(__dirname, 'public')

    app.use express.bodyParser()
    app.use express.methodOverride()
    app.use express.cookieParser 'secret'
    app.use express.session()
    app.use express.csrf()
    app.use app.router

    app.enable 'trust proxy'

app.configure 'development', () ->
    app.use express.errorHandler()
    app.locals.pretty = true

csrf = (req, res, next) ->
    res.locals.token = req.session._csrf
    next()

checkAuth = (req, res, next) ->
    entity = req.signedCookies.entity
    if entity and Users.IsAuthenticated(entity)
        next()
    else
        res.redirect '/login'

app.get '/', csrf, checkAuth, (req, res) ->
    console.log 'Accessing /'
    entity = req.signedCookies.entity

    user = Users.Get entity
    if not user
        console.error 'get: no valid user entry for ' + entity
        res.send 500, 'get: internal error'
        return

    cb = (err, headers, body) =>
        if err
            console.error 'error when fetching essays of ' + entity + ' :' + err
            essays = []
        else
            sessions[user.entity] ?= {}
            f = sessions[user.entity].form ?= {}
            f.summary ?= ''
            f.content ?= ''
            f.title ?= ''

            essays = body.posts

        if essays.map
            essays = essays.map (a) ->
                if not a.content or not a.content.title or a.content.title.length == 0
                    a.content.title = '(untitled)'
                a

        res.render 'all',
            essays: essays
            flash: sessions[user.entity].flash || emptyFlash()
        sessions[user.entity].flash = emptyFlash()

    user.tent.query(cb).types(ESSAY_TYPE)

app.get '/new', csrf, checkAuth, (req, res) ->
    res.render 'form',
        flash: emptyFlash()
        form: {}

app.get '/edit/:id', csrf, checkAuth, (req, res) ->
    entity = req.signedCookies.entity
    user = Users.Get entity
    id = req.param 'id'

    if not id
        sessions[entity].flash.error.push 'No id when editing a post'
        res.redirect '/'
        return

    user.tent.get id, (err, headers, essay) ->
        if err
            console.error 'retrieve by id: ' + err
            sessions[entity].flash.error.push 'Error when trying to retrieve post with id ' + id + ': ' + err
            res.redirect '/'
            return

        e = essay.post

        isPrivate = false
        if e.permissions and e.permissions.public != undefined and not e.permissions.public
            isPrivate = true

        form =
            title: e.content.title || '(untitled)'
            content: e.content.body || ''
            summary: e.content.excerpt || ''
            update: e.id
            isPrivate: isPrivate
            readUrl: '/read?user=' + qs.escape(entity) + '&id=' + qs.escape e.id

        res.render 'form',
            essays: []
            form: form
            flash: sessions[entity].flash || emptyFlash()
        sessions[entity].flash = emptyFlash()

app.get '/del/:id', csrf, checkAuth, (req, res) ->
    entity = req.signedCookies.entity
    user = Users.Get entity
    id = req.param 'id'

    if not id
        sessions[entity].flash.error.push 'no id when deleting an essay'
        res.redirect '/'
        return

    user.tent.delete id, (err) ->
        if err
            console.error 'deleting post ' + id + ': ' + err
            sessions[entity].flash.error.push 'Error when deleting an essay: ' + err
            res.redirect '/edit/' + id
        else
            sessions[entity].flash.success.push 'Deletion of essay was successful.'
            res.redirect '/'

stripScripts = (s) ->
    s.replace /<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>/gi, ''

app.get '/read', (req, res) ->
    id = req.param 'id'
    entity = req.param 'user'

    if not id or not entity
        res.send 'Missing parameter.'
        return

    entity = qs.unescape entity
    if not /^https?:\/\//ig.test entity
        res.send "The URL you've entered doesn't have a scheme (http or https)."
        return

    entity = entity.toLowerCase()
    if entity[ entity.length-1 ] == '/'
        entity = entity.slice 0, entity.length-1

    PublicClient.Get entity, (err, tent) ->
        if err
            res.send 500, 'Error when creating the public client: ' + err
            return
        tent.get id, (err2, headers, body) ->
            if err2
                res.send 500, 'Error when retrieving public post: ' + err2
                console.error 'Error when retrieving public post: ' + err2
            else
                essay = body.post
                res.render 'read',
                    essay:
                        title: essay.content.title
                        summary: stripScripts essay.content.excerpt
                        content: stripScripts essay.content.body

app.post '/new', checkAuth, (req, res) ->
    entity = req.signedCookies.entity
    user = Users.Get entity

    title = req.param 'title'
    summary = req.param 'summary'
    content = req.param 'content'
    isPrivate = !! req.param 'isPrivate'

    if not content or content.length == 0
        sessions[entity].form =
            title: title
            summary: summary

        sessions[entity].flash.error.push 'Missing parameter: no content'
        res.redirect '/'
        return

    essay =
        title: title || ''
        excerpt: summary || ''
        body: content

    updateId = req.param 'update'
    if updateId
        vbING = 'updating'
        noun = 'Update'
    else
        vbING = 'creating'
        noun = 'Creation'

    cb = (err) =>
        if err
            console.error 'error when ' + vbING + ' post: ' + err
            sessions[entity].flash.error.push 'An error happened when ' + vbING + ' post: ' + err
        else
            sessions[entity].flash.success.push noun + ' of your essay successful.'
            sessions[entity].form = {}
        res.redirect '/'

    if updateId
        user.tent.get updateId, (err, h, body) ->
            if err
                cb err
                return

            user.tent.update(updateId, body.post.version.id, cb)
                .type(ESSAY_TYPE)
                .content(essay)
                .permissions(!isPrivate)
    else
        user.tent.create(ESSAY_TYPE, cb)
            .publishedAt( +new Date() )
            .content(essay)
            .permissions(!isPrivate)

# Auth stuff
app.post '/login', (req, res) ->
    entity = req.param 'entity'

    if not entity
        res.send 'Missing parameter entity'
        return

    if not /^https?:\/\//ig.test entity
        res.send "The URL you've entered doesn't have a scheme (http or https), please <a href='/login'>retry</a>."
        return

    entity = entity.toLowerCase()
    if entity[ entity.length-1 ] == '/'
        entity = entity.slice 0, entity.length-1

    Users.LoadRegisteredUser entity, (err, user) =>
        if err
            console.error 'Server.Login: ' + err
            res.send 500, 'Internal error when retrieving client.'
            return

        if not user
            # client not registered, register the app
            console.log 'Registering: ' + entity
            Users.Register entity, config.app, (maybeError, auth) =>
                if maybeError
                    res.send 500, maybeError
                    return

                res.cookie 'entity', entity, {signed: true}
                sessions[entity] ?= {}
                sessions[entity].state = auth.state

                res.redirect auth.url
        else
            # already reg
            console.log 'Authenticating: ' + entity
            if PROD_MODE
                auth = Users.Identify entity

                res.cookie 'entity', entity, {signed:true}
                sessions[entity] ?= {}
                sessions[entity].state = auth.state

                res.redirect auth.url
            else
                userCred = Users.LoadUserCredentials entity, (err) =>
                    if err
                        res.send 500, err
                        return

                    res.cookie 'entity', entity, {signed:true}
                    sessions[entity] =
                        form: {}
                        flash: emptyFlash()
                    res.redirect '/'

app.get '/cb', (req, res) ->
    code = req.param 'code'
    state = req.param 'state'
    error = req.param 'error'

    if error
        console.error 'error when authenticating: ' + error
        if req.signedCookies.entity then res.clearCookie 'entity'
        res.send 'There was an error during authentication. Please retry by clicking <a href="/login">here</a>'
        return

    entity = req.signedCookies.entity
    if not entity
        res.send 'Error: no cookies. Please activate cookies for navigation on this site. Click <a href="/login">here</a> to retry.'
        return

    session = sessions[entity]
    if not session
        res.send 400
        return

    if state != session.state
        res.send 400, 'Error: misleading state.'
        return

    Users.TradeCode entity, code, (err) =>
        if err
            console.error err
            res.clearCookie 'entity'
            delete cacheEntities[entity]
            res.send 500, 'Error when trading the auth code: ' + err + '. Please retry <a href="/login">here</a>.'
        else
            session.form = {}
            session.flash = emptyFlash()
            res.redirect '/'

app.get '/logout', (req, res) ->
    entity = req.signedCookies.entity
    if entity
        res.clearCookie 'entity'
    if sessions[entity]
        delete sessions[entity]
    Users.Logout entity
    res.redirect '/login'

app.get '/login', csrf, (req, res) ->
    res.render 'login',
        flash: emptyFlash()

server = http.createServer(app).listen app.get('port'), () ->
    console.log 'Express server listening on port ' + app.get 'port'

