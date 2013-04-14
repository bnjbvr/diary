config = require './config'
PORT = config.port
APP = config.app
PROD_MODE = config.prod
Tent = require config.tentlib

express = require 'express'
http = require 'http'           # http.createServer
path = require 'path'           # path.join

fs = require 'fs'

###
# Map: < entity url, tent client >
###
cacheEntities = {}

###
# Saves app credentials. You can put anything you want there.
# In this example, app credentials are saved into app/[entity-name].json
###
saveAppCred = (entity, appInfo) ->
    filename = cleanEntity entity
    toSave =
        mac_key: appInfo.mac_key
        mac_key_id: appInfo.mac_key_id
        id: appInfo.id
    fs.writeFileSync 'app/' + filename + '.json', JSON.stringify toSave

# additional information about the entity
users = {}

###
# Saves user credentials. You can put anything you want there.
# In this example, user credentials are saved into user/[entity-name].json
###
saveUserCred = (entity, cred) ->
    filename = cleanEntity entity
    fs.writeFileSync 'user/' + filename + '.json', JSON.stringify cred
    users[entity] =
        entity: entity
        mac_key: cred.mac_key
        mac_key_id: cred.mac_key_id
        flash: []
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
retrieveTentClient = (entity) ->
    try
        filename = cleanEntity entity
        appCred = fs.readFileSync 'app/' + filename + '.json', {encoding:'utf8'}
        appCred = JSON.parse appCred
        cacheEntities[entity] = client = new Tent entity
        client.setAppCredentials appCred.mac_key, appCred.mac_key_id
        client.app.setId appCred.id

        client

    catch error
        console.error error
        null

# for dev mode, don't authenticate but use user credentials file
retrieveUserFile = (entity) ->
    filename = cleanEntity entity
    userCred = JSON.parse fs.readFileSync 'user/' + filename + '.json'
    return userCred

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

    postsGetParams =
        post_types: 'essay'
        entity: entity

    client.posts.get postsGetParams, (err, essays) ->
        if err
            console.error 'error when fetching essays of ' + entity + ' :' + err
            essays = []
        else
            users[entity] ?= {}
            f = users[entity].form ?= {}
            f.summary ?= ''
            f.content ?= ''
            f.title ?= ''

            if essays.map
                essays = essays.map (a) ->
                    a.content.title ?= '(untitled)'
                    a

            res.render 'form',
                essays: essays
                form: users[entity].form || {}
                flash: users[entity].flash || []
            users[entity].flash = []

app.get '/edit/:id', csrf, checkAuth, (req, res) ->
    entity = req.signedCookies.entity
    client = cacheEntities[ entity ]
    id = req.param 'id'

    if not id
        users[entity].flash.push 'No id when editing a post'
        res.redirect '/'
        return

    client.posts.getById id, {}, (err, essay) ->
        if err
            console.error 'retrieve by id: ' + err
            users[entity].flash.push 'Error when trying to retrieve post with id ' + id + ': ' + err
            res.redirect '/'
            return

        e = essay
        form =
            title: e.content.title || ''
            content: e.content.body || ''
            summary: e.content.excerpt || ''
            update: e.id

        res.render 'form',
            essays: []
            form: form
            flash: users[entity].flash || []
        users[entity].flash = []

app.get '/del/:id', csrf, checkAuth, (req, res) ->
    entity = req.signedCookies.entity
    client = cacheEntities[ entity ]
    id = req.param 'id'

    if not id
        users[entity].flash.push 'no id when deleting an essay'
        res.redirect '/'
        return

    client.posts.delete id, {}, (err) ->
        if err
            console.error 'deleting post ' + id + ': ' + err
            users[entity].flash.push 'Error when deleting an essay: ' + err
            res.redirect '/edit/' + id
        else
            users[entity].flash.push 'Deletion of essay was successful.'
            res.redirect '/'

app.post '/new', checkAuth, (req, res) ->
    entity = req.signedCookies.entity
    client = cacheEntities[ entity ]

    title = req.param 'title'
    summary = req.param 'summary'
    content = req.param 'content'

    if not content or content.length == 0

        users[entity].form =
            title: title
            summary: summary

        users[entity].flash.push 'Missing parameter: no content'

        res.redirect '/'
        return

    essay =
        title: title || ''
        excerpt: summary || ''
        body: content

    post =
        published_at: Math.floor( +new Date() / 1000 )
        mentions: []

        type: 'essay'
        content: essay
        permissions:
            public: true

    updateId = req.param 'update'
    if updateId
        vbING = 'updating'
        noun = 'Update'
    else
        vbING = 'creating'
        noun = 'Creation'

    cb = (err, enhanced) ->
        if err
            console.error 'error when ' + vbING + ' post: ' + err
            users[entity].flash.push 'An error happened when ' + vbING + ' post: ' + err
        else
            users[entity].flash.push noun + ' of your essay successful.'
            users[entity].form = {}
        res.redirect '/'

    if updateId
        client.posts.update updateId, post, cb
    else
        client.posts.create post, cb

# Auth stuff
app.post '/login', (req, res) ->
    entity = req.param 'entity'

    if not entity
        res.send 'Missing parameter entity'
        return

    if not /^https?:\/\//ig.test entity
        res.send "The URL you've entered doesn't have a scheme (http or https), please <a href='/login'>retry</a>."
        return

    client = retrieveTentClient entity
    if not client
        # client not registered, register the app
        console.log 'Registering: ' + entity
        client = new Tent entity
        client.app.register APP, (err, authUrl, appInfo) ->
            console.log 'callback of client is called'
            if err
                console.error err
                res.send 500, 'Error when registering the app. Are you sure you entered correctly your tent URL?'
            else
                saveAppCred entity, appInfo
                res.cookie 'entity', entity, {signed: true}
                cacheEntities[entity] = client
                res.redirect authUrl
    else
        # already reg
        console.log 'Authenticating: ' + entity
        if PROD_MODE
            client.app.getAuthUrl (err, authUrl, appInfo) ->
                if err
                    console.error err
                    res.send 500, 'Error when authenticating the user: ' + err
                else
                    res.cookie 'entity', entity, {signed:true}
                    res.redirect authUrl
        else
            userCred = retrieveUserFile entity
            client.setUserCredentials userCred.mac_key, userCred.mac_key_id
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

    client.app.tradeCode code, state, (err, comp) ->
        if err
            console.error err

            res.clearCookie 'entity'
            delete cacheEntities[entity]

            res.send 500, 'Error when trading the auth code. Please retry <a href="/login">here</a>.'
        else
            saveUserCred entity, comp
            res.redirect '/'

app.get '/logout', (req, res) ->
    entity = req.signedCookies.entity
    if entity
        res.clearCookie 'entity'
    if cacheEntities[entity]
        delete cacheEntities[entity]
    res.redirect '/login'

app.get '/login', csrf, (req, res) ->
    res.render 'login'

server = http.createServer(app).listen app.get('port'), () ->
    console.log 'Express server listening on port ' + app.get 'port'

