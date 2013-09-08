sqlite = require 'sqlite3'
config = require './config'

if config.prod
    db = new sqlite.Database './diary.db'
else
    db = new sqlite.Database ':memory:'

db.run 'CREATE TABLE registration (entity TEXT PRIMARY KEY, appId TEXT, credentials TEXT)', (err) ->
    if err
        console.warn err

exports.saveUserCred = (entity, appInfo, cb) ->
    appId = appInfo.id
    cred = JSON.stringify appInfo.cred

    db.run "INSERT INTO registration VALUES (?, ?, ?)", entity, appId, cred, (err) ->
        if err
            cb 'Error when inserting a new registration: ' + err
            console.error 'Error when inserting a new registration: ' + err
            return
        cb null

tryFindUser = exports.tryFindUser = (entity, cb) ->
    db.get 'SELECT * FROM registration WHERE entity = ?', entity, (err, row) ->
        if err
            cb 'Error when retrieving a user: ' + err
            console.error 'Error when retrieving a user: ' + err
            return

        # not found
        if not row
            cb null, null
            return

        appInfo =
            id: row.appId
            cred: JSON.parse row.credentials
        cb null, appInfo
