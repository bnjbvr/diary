Users = require '../models/users'

exports.Csrf = (req, res, next) ->
    res.locals.token = req.session._csrf
    next()

exports.CheckAuth = (req, res, next) ->
    entity = req.signedCookies.entity
    if entity and Users.IsAuthenticated(entity)
        next()
    else
        res.cookie 'next', req.url, {signed:true}
        res.redirect '/login'
