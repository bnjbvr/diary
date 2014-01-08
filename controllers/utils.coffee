qs = require 'querystring'

exports.CheckValidEntity = (entity) ->
    if not entity
        return {error: "Missing parameter: entity."}

    if not /^https?:\/\//ig.test entity
        return {error: "The entity you've entered doesn't contain a scheme (http or https)."}

    entity = qs.unescape entity
    entity = entity.toLowerCase()
    if entity[ entity.length-1 ] == '/'
        entity = entity.slice 0, entity.length-1
    return {entity: entity}

exports.StripScripts = (s) ->
    s.replace /<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>/gi, ''

exports.MakePageLink = (entity) ->
    '/page?user=' + qs.escape entity

