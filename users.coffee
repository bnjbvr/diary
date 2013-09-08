Ta = require 'tent-auth'
Tr = require 'tent-request'
Td = require 'tent-discover'
fs = require 'fs'

config = require './config'
PROD_MODE = config.prod

class UserSession
    constructor: () ->
        @cleanInfos()
        @cleanFlash()
        @

    pushError: (msg) ->
        @flash.error.push msg
        @

    pushSuccess: (msg) ->
        @flash.success.push msg
        @

    getFlash: () ->
        flash = @flash
        @cleanFlash()
        flash

    cleanFlash: () ->
        @flash =
            error: []
            success: []
        @

    cleanInfos: () ->
        @form = {}
        @

cacheUsers = {}

class User
    constructor: (@entity, @shortEntity) ->
        @meta = null
        @appInfo = null
        @credentials = null
        @tent = null
        @session = new UserSession

    saveAppInfo: (appInfo) ->
        # lazy implementation: saves app info in a file
        @appInfo = appInfo
        filename = 'app/' + @shortEntity + '.json'
        fs.writeFileSync filename, JSON.stringify appInfo
        @

    saveUserCred: (cred, cb) ->
        @credentials = cred

        if not @meta
            Td @entity, (maybeError, meta) =>
                if maybeError
                    console.error 'Users.User.saveUserCred.callback error: ' + maybeError
                    cb maybeError
                    return

                meta = @saveMeta meta
                @tent = Tr.createClient meta, @credentials
                cb null
        else
            @tent = Tr.createClient @meta, @credentials
            cb null

        if not PROD_MODE
            # lazy implementation: saves user credentials in a file
            filename = 'user/' + @shortEntity + '.json'
            fs.writeFileSync filename, JSON.stringify cred

    isAuthenticated: () ->
        @credentials != null

    saveMeta: (meta) ->
        if meta.post
            meta = meta.post
        if meta.content
            meta = meta.content
        @meta = meta
        @meta

    pushError: (msg) ->
        @session.pushError msg

    pushSuccess: (msg) ->
        @session.pushSuccess msg

### STATIC METHODS ###
# Cleans an entity name by removing http(s) and remaining slashes
CleanEntity = (entity) ->
    cleaned = entity.replace /http(s)?:\/\//ig, ''
    cleaned = cleaned.replace /:/g, '-'
    cleaned = cleaned.replace /\//g, ''
    return cleaned

# Retrieves the user
GetUser = (entity) ->
    short = CleanEntity entity
    cacheUsers[short] ?= new User entity, short
    cacheUsers[short]

### PUBLIC METHODS ###
###
# Registers the given entity for the given app
#
#   entity -> str
#   app -> app object, as specified by tent docs
#   cb -> function(maybeError, {url: 'http://entity.tent.com/auth/', state: '0147200001'})
###
exports.Register = (entity, app, cb) ->
    user = GetUser entity
    Td entity, (maybeError, meta) =>
        if maybeError
            console.error 'Users.Register.discovery callback error: ' + maybeError
            cb 'Error on discovery: ' + maybeError
            return

        meta = user.saveMeta meta
        Ta.registerApp meta, app, (regError, appCred, appId) =>
            if regError
                console.error 'Users.Register.registerApp callback error: ' + regError
                cb 'Error on register: ' + regError
                return

            user.saveAppInfo
                id: appId
                cred: appCred

            auth = Ta.generateURL meta, appId
            cb null, auth

###
# Returns an auth object, i.e. {authUrl: '', state: ''}
#
#   entity -> str
###
exports.Identify = (entity) ->
    user = GetUser entity
    Ta.generateURL user.meta, user.appInfo.id

###
# True if the entity is already authenticated, false otherwise.
###
exports.IsAuthenticated = (entity) ->
    GetUser(entity).isAuthenticated()

###
# Simply returns the user
#
#   entity -> ''
###
exports.Get = (entity) ->
    user = GetUser(entity)
    if user and user.isAuthenticated()
        user
    else
        null

###
# Returns a tent client corresponding to the given entity, or null
# if the entity hasn't registered before.
#
# The entity MUST have registered the app before, which means app credentials
# for this entity should be found.
#
#   entity -> str
#   cb -> function (err, userInstance) {}
###
exports.LoadRegisteredUser = (entity, cb) ->
    try
        user = GetUser entity
        appInfo = fs.readFileSync 'app/' + user.shortEntity + '.json', {encoding:'utf8'}
        appInfo = JSON.parse appInfo

        user.saveAppInfo appInfo
        Td entity, (maybeError, meta) =>
            if maybeError
                cb maybeError, null
                return
            user.saveMeta meta
            cb null, user

    catch error
        console.log 'Users.LoadRegisteredUser warning: ' + error
        cb null, null

    true

###
# Exchanges permanent app credentials against client credentials
#
#   entity -> str
#   code -> str
#   cb -> function(maybeError){}
###
exports.TradeCode = (entity, code, cb) ->
    user = GetUser entity
    Ta.tradeCode user.meta, user.appInfo.cred, code, (err, userCred) =>
        if err
            console.error 'Users.TradeCode.tradeCode callback error: ' + err
            cb err
        else
            user.saveUserCred userCred, cb

###
# Cheated method to retrieve user credentials, in dev mode.
#
#   entity -> str
#   cb -> function(maybeError){}
###
exports.LoadUserCredentials = (entity, cb) ->
    user = GetUser entity
    userCred = JSON.parse fs.readFileSync 'user/' + user.shortEntity + '.json'
    user.saveUserCred userCred, cb
    true

###
# Logouts the user
#
#   entity -> str
###
exports.Logout = (entity) ->
    if cacheUsers[entity]
        delete cacheUsers[entity]
