sqlite = require 'sqlite3'
config = require './config'

if config.prod
    db = new sqlite.Database './diary.db'
else
    db = new sqlite.Database ':memory:'

INITIAL_CREATION = ['CREATE TABLE registration (entity TEXT PRIMARY KEY, appId TEXT, credentials TEXT);',
    'CREATE TABLE feed (entity TEXT, id TEXT, title TEXT, pubDate INT, UNIQUE (entity, id) ON CONFLICT REPLACE);']

for stmt in INITIAL_CREATION
    db.run stmt, (err) ->
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

exports.tryFindUser = (entity, cb) ->
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

exports.SaveForGlobalFeed = (post, cb) ->
    db.run "INSERT INTO feed VALUES (?, ?, ?, ?)", post.entity, post.id, post.content.title, post.published_at, (err) =>
        if err
            console.error 'Database.SaveForGlobalFeed: ' + err
            cb err
            return
        cb null

exports.GetGlobalFeed = (cb) ->
    db.all "SELECT * FROM feed ORDER BY pubDate DESC LIMIT 20", (err, posts) =>
        if err
            console.error 'Database.GetGlobalFeed: ' + err
            cb err, null
            return
        cb null, posts
