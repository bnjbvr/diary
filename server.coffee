# Imports
express = require 'express'
http    = require 'http'           # http.createServer
path    = require 'path'           # path.join
qs      = require 'querystring'

Users           = require './users'
Backend         = require './backend'
PublicClient    = require './public-client'
Database        = require './database'

# TODO
# - add successes messages

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

    # helpers for jade
    app.locals.formatDate = (n) ->
        date = new Date n
        'the ' + (1+date.getMonth()) + '/' + date.getDate() + '/' + date.getFullYear() + ' at ' + date.getHours() + ':' + date.getMinutes() + ':' + date.getSeconds()

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
        res.cookie 'next', req.url, {signed:true}
        res.redirect '/login'

checkValidEntity = (entity) ->
    if not entity
        return {error: "Missing parameter: entity."}

    if not /^https?:\/\//ig.test entity
        return {error: "The entity you've entered doesn't contain a scheme (http or https)."}

    entity = entity.toLowerCase()
    if entity[ entity.length-1 ] == '/'
        entity = entity.slice 0, entity.length-1
    return {entity: entity}

showErrorPage = (user, res) ->
    res.render 'loggedin',
        flash: user.session.getFlash()

stripScripts = (s) ->
    s.replace /<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>/gi, ''

# Get all's users route
app.get '/my', csrf, checkAuth, (req, res) ->
    entity = req.signedCookies.entity
    user = Users.Get entity

    Backend.GetEssays user, (err, essays) =>
        if err
            user.pushError err
            showErrorPage user, res
            return

        user.session.cleanInfos()

        for e in essays
            e.readLink = '/read?user=' + qs.escape(entity) + '&id=' + qs.escape e.id

        res.render 'user_all',
            essays: essays
            flash: user.session.getFlash()

# Get all subscribed route
app.get '/', csrf, checkAuth, (req, res) ->
    entity = req.signedCookies.entity
    user = Users.Get entity

    Backend.GetFeed user, (err, essays) =>
        if err
            user.pushError err
            showErrorPage user, res
            return

        user.session.cleanInfos()
        for e in essays
            e.readLink = '/friend?user=' + qs.escape(e.entity) + '&id=' + qs.escape e.id
        res.render 'all',
            essays: essays
            flash: user.session.getFlash()

app.get '/global', csrf, checkAuth, (req, res) ->
    user = Users.Get req.signedCookies.entity
    Database.GetGlobalFeed (err, posts) =>
        if err
            user.pushError 'When retrieving the global feed, ' + err
            showErrorPage user, res
            return
        posts = posts.map (p) ->
            p.readLink = '/friend?user=' + qs.escape(p.entity) + '&id=' + qs.escape p.id
            p
        res.render 'global',
            essays: posts
            flash: user.session.getFlash()

# Get subscriptions
app.get '/subs', csrf, checkAuth, (req, res) ->
    entity = req.signedCookies.entity
    user = Users.Get entity

    Backend.GetSubscriptions user, (err, subs) ->
        if err
            user.pushError err
            showErrorPage user, res
            return

        res.render 'subs_list',
            subs: subs
            flash: user.session.getFlash()

# Adds a subscription
app.post '/subs/new', csrf, checkAuth, (req, res) ->
    entity = req.signedCookies.entity
    user = Users.Get entity

    # check input
    subscription = req.param 'entity'
    validCheck = checkValidEntity subscription
    if validCheck.error
        user.pushError validCheck.error
        res.redirect '/subs'
        return

    subscription = validCheck.entity
    subTent = PublicClient.Get subscription, (err, _) =>
        if err
            user.pushError err
            res.redirect '/subs'
            return

        Backend.AddSubscription user, subscription, (err2) =>
            if err2
                user.pushError err2
            res.redirect '/subs'

# Get friend article
app.get '/friend', csrf, checkAuth, (req, res) ->
    id = req.param 'id'
    entity = req.param 'user'
    user = Users.Get req.signedCookies.entity

    if not id
        user.pushError 'Missing parameter: id'
        showErrorPage user, res
        return

    validCheck = checkValidEntity qs.unescape entity
    if validCheck.error
        user.pushError validCheck.error
        showErrorPage user, res
        return
    entity = validCheck.entity

    Backend.GetFriendEssayById user, entity, id, (err, essay, profile) =>
        if err
            user.pushError err
            showErrorPage user, res
            return

        res.render 'friend',
            essay:
                title: essay.content.title
                summary: stripScripts essay.content.excerpt
                content: stripScripts essay.content.body
            profile: profile
            entity: entity if entity != user.entity
            flash: user.session.getFlash()

# Print new post form
app.get '/my/new', csrf, checkAuth, (req, res) ->
    user = Users.Get req.signedCookies.entity

    if user.session.flash.error.length == 0
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
        res.redirect '/my'
        return

    Backend.GetEssayById user, id, (err, e) ->
        if err
            user.session.pushError err
            res.redirect '/my'
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

        res.render 'form',
            form: form
            flash: user.session.getFlash()

# Delete post by id
app.get '/del/:id', csrf, checkAuth, (req, res) ->
    entity = req.signedCookies.entity
    user = Users.Get entity
    id = req.param 'id'

    if not id
        user.pushError 'no id when deleting an essay'
        res.redirect '/my'
        return

    Backend.DeleteEssayById user, id, (err) ->
        if err
            user.ushError err
            res.redirect '/edit/' + id
        else
            user.pushSuccess 'Deletion of essay was successful.'
            Database.MaybeDeleteFromFeed {entity: entity, id: id}, (err) =>
                res.redirect '/my'


# Reader
app.get '/read', (req, res) ->
    id = req.param 'id'
    entity = req.param 'user'

    if not id
        res.send 400, 'Missing parameter: id'
        return

    validCheck = checkValidEntity qs.unescape entity
    if validCheck.error
        res.send 400, validCheck.error
        return
    entity = validCheck.entity

    PublicClient.Get entity, (err, tent) ->
        if err
            res.send 500, err
            return

        Backend.GetEssayById {tent:tent}, id, (err2, essay) ->
            if err2
                res.send 500, err
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
    updateId = req.param 'update'

    if not content or content.length == 0
        user.session.form =
            title: title
            summary: summary
            isPrivate: isPrivate
            update: updateId

        user.pushError 'Missing parameter: no content'
        res.redirect '/my/new'
        return

    essay =
        title: title || ''
        excerpt: summary || ''
        body: content

    if updateId
        vbING = 'updating'
        noun = 'Update'
    else
        vbING = 'creating'
        noun = 'Creation'

    cb = (err, post) =>
        if err
            user.pushError 'An error happened when ' + vbING + ' post: ' + err
        else
            user.pushSuccess noun + ' of your essay successful.'
            user.session.cleanInfos()
            if not isPrivate
                Database.SaveForGlobalFeed post, (err2) =>
                    if err2
                        user.pushError 'Error when adding the post to the global feed: ' + err2
                    res.redirect '/my'
            else
                Database.MaybeDeleteFromFeed post, (_) =>
                    res.redirect '/my'

    if updateId
        Backend.UpdateEssay user, updateId, essay, isPrivate, cb
    else
        Backend.CreateEssay user, essay, isPrivate, cb


# Auth stuff
app.post '/login', (req, res) ->
    entity = req.param 'entity'

    # check input
    validCheck = checkValidEntity entity
    if validCheck.error
        res.send 400, validCheck.error
        return
    entity = validCheck.entity

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

                    if req.signedCookies.next
                        nextUrl = req.signedCookies.next
                        res.clearCookie 'next'
                        res.redirect nextUrl
                    else
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
            if req.signedCookies.next
                nextUrl = req.signedCookies.next
                res.clearCookie 'next'
                res.redirect nextUrl
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
