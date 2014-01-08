config = require '../config'

Utils = require './utils'
Users = require '../models/users'

##############
# Auth stuff #
##############

states = {}

exports.login = (req, res) ->
    entity = req.param 'entity'

    # check input
    validCheck = Utils.CheckValidEntity entity
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
            if config.prod
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

exports.callback = (req, res) ->
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

exports.logout = (req, res) ->
    entity = req.signedCookies.entity
    if entity
        res.clearCookie 'entity'
    Users.Logout entity
    res.redirect '/login'

exports.loginForm = (req, res) ->
    res.render 'login'

