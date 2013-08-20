Td = require 'tent-discover'
Tr = require 'tent-request'

cacheReaders = {}

exports.Get = (entity, cb) ->
    if cacheReaders[entity]
        cb null, cacheReaders[entity]
        return

    Td entity, (maybeErr, meta) ->
        if maybeErr
            console.error 'PublicClient.make callback error: ' + maybeErr
            cb maybeErr
            return
        cacheReaders[entity] = Tr.createClient meta.post.content
        cb null, cacheReaders[entity]

    true

