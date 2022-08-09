from std/tables import Table, `[]=`, `$`, `[]`
from std/json import parseJson, to, `$`
import std/jsonutils
from std/os import fileExists
from std/httpclient import newAsyncHttpClient, get, Http200, code, close

import std/times
import std/locks

import pkg/prologue

type
  Sites = Table[string, string]
  Cache = Table[string, tuple[online: bool, time: int64]]

proc getCache(file: string): Cache =
  ## Retrieves the cache from a json file
  if fileExists file:
    result = file.readFile.parseJson.to Cache
proc setCache(file: string; data: Cache) =
  ## Saves the cache to a json file
  file.writeFile data.toJson.`$`

proc checkSiteOn(site: string): Future[bool] {.async.} =
  let
    client = newAsyncHttpClient()
    res = await client.get site
  result = res.code == Http200
  close client

proc isOn(file, site: string; delay: int): Future[bool] {.async.} =
  ## Check if site is on and save it to cache
  var cache = getCache file
  let now = getTime()

  if not cache.hasKey site:
    cache[site] = (false, 0'i64)

  result = cache[site].online

  if cache[site].time.fromUnix + delay.milliseconds <= now:
    result = await checkSiteOn site
    cache[site] = (result, now.toUnix)
    file.setCache cache

proc itsOn*(sitesJson, cacheJson: string; delay: int) =
  var sitesLock: Lock
  let sites {.guard: sitesLock.} = sitesJson.readFile.parseJson.to Sites

  proc check(ctx: Context) {.async.} =
    ## Checks if website is online
    let id = ctx.getPathParams("id", "")
    var site = ""
    {.gcsafe.}:
      withLock sitesLock:
        if sites.hasKey id:
          site = sites[id]

    let on = await cacheJson.isOn(site, delay)
    resp if on: "1" else: "0"
    
  initLock sitesLock

  let app = newApp()
  app.get("/{id}", check)
  run app

  deinitLock sitesLock


when isMainModule:
  import pkg/cligen
  dispatch itsOn
