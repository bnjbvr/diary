# Imports
express = require 'express'
http    = require 'http'           # http.createServer
path    = require 'path'           # path.join
qs      = require 'querystring'

Users           = require './users'
Backend         = require './backend'
PublicClient    = require './public-client'

# Config of the app
config = require './config'
PORT = config.port
APP = config.app
PROD_MODE = config.prod

states = {}

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

# Get all route
app.get '/', csrf, checkAuth, (req, res) ->
    console.log 'Accessing /'
    entity = req.signedCookies.entity

    user = Users.Get entity
    if not user
        console.error 'get: no valid user entry for ' + entity
        res.send 500, 'internal error'
        return

    Backend.GetEssays user, (err, essays) =>
        if err
            res.send 500, err
            return

        user.session.cleanInfos()
        res.render 'all',
            essays: essays
            flash: user.session.getFlash()

# Print new post form
app.get '/new', csrf, checkAuth, (req, res) ->
    user = Users.Get req.signedCookies.entity
    if not user
        console.error '/new: no valid user entry for ' + user.entity
        res.send 500, 'internal error'
        return

    user.session.cleanInfos()
    res.render 'form',
        form: user.session.form
        flash: user.session.getFlash()

# Print edit post form
app.get '/edit/:id', csrf, checkAuth, (req, res) ->
    entity = req.signedCookies.entity
    user = Users.Get entity
    id = req.param 'id'

    if not id
        user.session.pushError 'No id when editing a post'
        res.redirect '/'
        return

    Backend.GetEssayById user, id, (err, e) ->
        if err
            user.session.pushError 'Error when trying to retrieve post with id ' + id + ': ' + err
            res.redirect '/'
            return

        isPrivate = false
        if e.permissions and e.permissions.public != undefined and not e.permissions.public
            isPrivate = true

        form =
            title: e.content.title || ''
            content: e.content.body || ''
            summary: e.content.excerpt || ''
            update: e.id
            isPrivate: isPrivate
            readUrl: '/read?user=' + qs.escape(entity) + '&id=' + qs.escape e.id

        res.render 'form',
            form: form
            flash: user.session.getFlash()

# Delete post by id
app.get '/del/:id', csrf, checkAuth, (req, res) ->
    entity = req.signedCookies.entity
    user = Users.Get entity
    id = req.param 'id'

    if not id
        user.session.pushError 'no id when deleting an essay'
        res.redirect '/'
        return

    Backend.DeleteEssayById user, id, (err) ->
        if err
            user.session.pushError err
            res.redirect '/edit/' + id
        else
            user.session.pushSuccess 'Deletion of essay was successful.'
            res.redirect '/'

# Reader
stripScripts = (s) ->
    s.replace /<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>/gi, ''

app.get '/read', (req, res) ->
    id = req.param 'id'
    entity = req.param 'user'

    if not id or not entity
        res.send 500, 'Missing parameter.'
        return

    entity = qs.unescape entity
    if not /^https?:\/\//ig.test entity
        res.send 500, "The entity URL you've entered doesn't have a scheme (http or https)."
        return

    entity = entity.toLowerCase()
    if entity[ entity.length-1 ] == '/'
        entity = entity.slice 0, entity.length-1

    PublicClient.Get entity, (err, tent) ->
        if err
            res.send 500, 'Error when creating the public client: ' + err
            return

        Backend.GetEssayById {tent:tent}, id, (err2, essay) ->
            if err2
                res.send 500, 'Error when retrieving public post: ' + err2
                return

            res.render 'read',
                essay:
                    title: essay.content.title
                    summary: stripScripts essay.content.excerpt
                    content: stripScripts essay.content.body

# New essay
app.post '/new', checkAuth, (req, res) ->
    entity = req.signedCookies.entity
    user = Users.Get entity

    title = req.param 'title'
    summary = req.param 'summary'
    content = req.param 'content'
    isPrivate = !! req.param 'isPrivate'

    if not content or content.length == 0
        user.session.form =
            title: title
            summary: summary

        user.session.pushError 'Missing parameter: no content'
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
            user.session.pushError 'An error happened when ' + vbING + ' post: ' + err
        else
            user.session.pushSuccess noun + ' of your essay successful.'
            user.session.cleanInfos()
        res.redirect '/'

    if updateId
        Backend.UpdateEssay user, updateId, essay, isPrivate, cb
    else
        Backend.CreateEssay user, essay, isPrivate, cb


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
                states[entity] = auth.state
                res.redirect auth.url
        else
            # already reg
            console.log 'Authenticating: ' + entity
            if PROD_MODE
                auth = Users.Identify entity

                res.cookie 'entity', entity, {signed:true}
                states[entity] = auth.state
                res.redirect auth.url
            else
                userCred = Users.LoadUserCredentials entity, (err) =>
                    if err
                        res.send 500, err
                        return

                    res.cookie 'entity', entity, {signed:true}
                    user.session.cleanInfos()
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

    formerState = states[entity] || null
    if not formerState
        res.send 400
        return

    if state != formerState
        res.send 400, 'Error: misleading state.'
        return

    Users.TradeCode entity, code, (err) =>
        if err
            console.error err
            res.clearCookie 'entity'
            res.send 500, 'Error when trading the auth code: ' + err + '. Please retry <a href="/login">here</a>.'
        else
            res.redirect '/'

app.get '/logout', (req, res) ->
    entity = req.signedCookies.entity
    if entity
        res.clearCookie 'entity'
    Users.Logout entity
    res.redirect '/login'

app.get '/login', csrf, (req, res) ->
    res.render 'login'

server = http.createServer(app).listen app.get('port'), () ->
    console.log 'Express server listening on port ' + app.get 'port'

