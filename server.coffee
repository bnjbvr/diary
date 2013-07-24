config = require './config'
PORT = config.port
APP = config.app
PROD_MODE = config.prod

ESSAY_TYPE = 'https://tent.io/types/essay/v0#'

Td = require 'tent-discover'
Ta = require 'tent-auth'
Tr = require 'tent-request'

express = require 'express'
http = require 'http'           # http.createServer
path = require 'path'           # path.join

qs = require 'querystring'
fs = require 'fs'

###
# Map: < entity url, tent client >
###
cacheEntities = {}

###
# Saves app credentials. You can put anything you want there.
# In this example, app credentials are saved into app/[entity-name].json
###
saveAppCred = (entity, client) ->
    filename = cleanEntity entity
    toSave = client.app
    fs.writeFileSync 'app/' + filename + '.json', JSON.stringify toSave

# additional information about the entity
users = {}

emptyFlash = ->
    error: []
    success: []

###
# Saves user credentials. You can put anything you want there.
# In this example, user credentials are saved into user/[entity-name].json
###
saveUserCred = (entity, cred) ->
    filename = cleanEntity entity
    fs.writeFileSync 'user/' + filename + '.json', JSON.stringify cred
    cacheEntities[entity].credentials = cred
    users[entity] =
        tent: Tr.createClient cacheEntities[entity].meta, cred
        # server related
        flash: emptyFlash()
        form: {}

###
# Returns a tent client corresponding to the given entity, or null
# if the entity hasn't registered before.
#
# The entity MUST have registered the app before, which means app credentials
# for this entity should be findable.
#
# In this example, app credentials are looked upon in a file that should be contained in the app directory, with the
# form [entity-name].json
###
retrieveTentClient = (entity, cb) ->
    try
        filename = cleanEntity entity
        appCred = fs.readFileSync 'app/' + filename + '.json', {encoding:'utf8'}
        appCred = JSON.parse appCred

        cacheEntities[entity] = client = {}
        client.app = appCred
        Td entity, (maybeError, meta) =>
            if maybeError
                cb maybeError, null
                return
            client.meta = meta.post.content
            cb null, client

    catch error
        cb null, null

    true

# for dev mode, don't authenticate but use user credentials file
retrieveUserFile = (entity) ->
    filename = cleanEntity entity
    userCred = JSON.parse fs.readFileSync 'user/' + filename + '.json'

    if not cacheEntities[entity] or not cacheEntities[entity].meta
        throw 'retrieveUserFile: No meta found for ' + entity
        return

    cacheEntities[entity].credentials = userCred
    users[entity] =
        tent: Tr.createClient cacheEntities[entity].meta, userCred
        # server related
        flash: emptyFlash()
        form: {}
    true

# cleans an entity name by removing http(s) and remaining slashes
cleanEntity = (entity) ->
    cleaned = entity.replace /http(s)?:\/\//ig, ''
    cleaned = cleaned.replace /\//g, ''
    return cleaned

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
    if entity and cacheEntities[entity]
        next()
    else
        res.redirect '/login'

app.get '/', csrf, checkAuth, (req, res) ->
    console.log 'Accessing /'
    entity = req.signedCookies.entity
    client = cacheEntities[ entity ]
    # if the user is authentified

    cb = (err, headers, body) =>
        if err
            console.error 'error when fetching essays of ' + entity + ' :' + err
            essays = []
        else
            if not users[entity]
                console.error 'get: no users.entity for ' + entity
                res.send 500, 'get: internal error'
                return

            f = users[entity].form ?= {}
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
            flash: users[entity].flash || emptyFlash()
        users[entity].flash = emptyFlash()

    users[entity].tent.query(cb).types(ESSAY_TYPE)

app.get '/new', csrf, checkAuth, (req, res) ->
    res.render 'form',
        flash: emptyFlash()
        form: {}

app.get '/edit/:id', csrf, checkAuth, (req, res) ->
    entity = req.signedCookies.entity
    client = users[ entity ]
    id = req.param 'id'

    if not id
        users[entity].flash.error.push 'No id when editing a post'
        res.redirect '/'
        return

    client.tent.get id, (err, headers, essay) ->
        if err
            console.error 'retrieve by id: ' + err
            users[entity].flash.error.push 'Error when trying to retrieve post with id ' + id + ': ' + err
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
            flash: users[entity].flash || emptyFlash()
        users[entity].flash = emptyFlash()

app.get '/del/:id', csrf, checkAuth, (req, res) ->
    entity = req.signedCookies.entity
    client = users[ entity ]
    id = req.param 'id'

    if not id
        users[entity].flash.error.push 'no id when deleting an essay'
        res.redirect '/'
        return

    client.tent.delete id, (err) ->
        if err
            console.error 'deleting post ' + id + ': ' + err
            users[entity].flash.error.push 'Error when deleting an essay: ' + err
            res.redirect '/edit/' + id
        else
            users[entity].flash.success.push 'Deletion of essay was successful.'
            res.redirect '/'

readers = {}
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

    makePublicClient = (cb) ->
        if readers[entity]
            cb null, readers[entity]
            return
        Td entity, (maybeErr, meta) ->
            if maybeErr
                cb maybeErr
                return
            readers[entity] = Tr.createClient meta.post.content
            cb null, readers[entity]
        true

    makePublicClient (err, client) ->
        if err
            res.send 'Error when creating client for ' + entity
            console.error 'Error when creating client for ' + entity + ': ' + err
            return
        client.get id, (err2, headers, body) ->
            if err2
                res.send 'Error when retrieving post: ' + err2
                console.error 'Error when retrieving post: ' + err2
            else
                essay = body.post
                res.render 'read',
                    essay:
                        title: essay.content.title
                        summary: stripScripts essay.content.excerpt
                        content: stripScripts essay.content.body

app.post '/new', checkAuth, (req, res) ->
    entity = req.signedCookies.entity
    client = cacheEntities[ entity ]

    title = req.param 'title'
    summary = req.param 'summary'
    content = req.param 'content'
    isPrivate = !! req.param 'isPrivate'

    if not content or content.length == 0
        users[entity].form =
            title: title
            summary: summary

        users[entity].flash.error.push 'Missing parameter: no content'
        res.redirect '/'
        return

    essay =
        title: title || ''
        excerpt: summary || ''
        body: content

    tent = users[entity].tent

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
            users[entity].flash.error.push 'An error happened when ' + vbING + ' post: ' + err
        else
            users[entity].flash.success.push noun + ' of your essay successful.'
            users[entity].form = {}
        res.redirect '/'

    if updateId
        tent.get updateId, (err, h, body) ->
            if err
                cb err
                return

            tent.update(updateId, body.post.version.id, cb)
                .type(ESSAY_TYPE)
                .content(essay)
                .permissions(!isPrivate)
    else
        tent.create(ESSAY_TYPE, cb)
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

    retrieveTentClient entity, (err, client) =>
        if err
            console.error err
            res.send 500, 'Internal error when retrieving client.'
            return

        if not client
            # client not registered, register the app
            console.log 'Registering: ' + entity
            client = {}
            Td entity, (maybeError, meta) =>
                if maybeError
                    console.error maybeError
                    res.send 500, 'Error on discovery: ' + maybeError
                    return

                meta = client.meta = meta.post.content
                Ta.registerApp meta, config.app, (regError, appCred, appId) =>
                    if regError
                        console.error regError
                        res.send 500, 'Error on register: ' + regError
                        return

                    client.app =
                        id: appId
                        cred: appCred

                    client.auth = Ta.generateURL meta, appId

                    saveAppCred entity, client
                    cacheEntities[entity] = client
                    res.cookie 'entity', entity, {signed: true}
                    res.redirect client.auth.url
        else
            # already reg
            console.log 'Authenticating: ' + entity
            if PROD_MODE
                client.auth = Ta.generateURL client.meta, client.app.id
                res.cookie 'entity', entity, {signed:true}
                res.redirect client.auth.url
            else
                userCred = retrieveUserFile entity
                res.cookie 'entity', entity, {signed:true}
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

    client = cacheEntities[ entity ]
    if not client
        res.send 400
        return

    if state != client.auth.state
        res.send 400, 'Error: misleading state.'
        return

    Ta.tradeCode client.meta, client.app.cred, code, (err, userCred) =>
        if err
            console.error err
            res.clearCookie 'entity'
            delete cacheEntities[entity]
            res.send 500, 'Error when trading the auth code: ' + err + '. Please retry <a href="/login">here</a>.'
        else
            saveUserCred entity, userCred
            res.redirect '/'

app.get '/logout', (req, res) ->
    entity = req.signedCookies.entity
    if entity
        res.clearCookie 'entity'
    if cacheEntities[entity]
        delete cacheEntities[entity]
    if users[entity]
        delete users[entity]
    res.redirect '/login'

app.get '/login', csrf, (req, res) ->
    res.render 'login',
        flash: emptyFlash()

server = http.createServer(app).listen app.get('port'), () ->
    console.log 'Express server listening on port ' + app.get 'port'

