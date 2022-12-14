from std/tables import Table, `[]=`, `$`, `[]`
from std/json import parseJson, to, `$`
import std/jsonutils
from std/os import fileExists
from std/uri import parseUri

import std/times
import std/locks
import std/[asyncdispatch, net, asyncnet]

import pkg/prologue
from pkg/harpoon import fetch, newDefaultHeaders

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

proc checkSiteUp(site: string; timeout: int): Future[bool] {.async.} =
  let socket: Socket = newSocket()
  try:
    let res = socket.fetch(parseUri site, HttpGet, newDefaultHeaders "", timeout = timeout)
    result = res.code == Http200
  except:
    discard
  finally:
    close socket
    

proc isUp(file, site: string; delay, timeout: int): Future[bool] {.async.} =
  ## Check if site is on and save it to cache
  var cache = getCache file
  let now = getTime()

  if not cache.hasKey site:
    cache[site] = (false, 0'i64)

  result = cache[site].online

  if cache[site].time.fromUnix + delay.milliseconds <= now:
    result = await checkSiteUp(site, timeout)
    cache[site] = (result, now.toUnix)
    file.setCache cache

proc itsUp*(sitesJson, cacheJson: string; delay, timeout: int) =
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
    if site.len > 0:
      let on = await cacheJson.isUp(site, delay, timeout)
      resp if on: "1" else: "0"
    else:
      resp "0", Http404
    
  initLock sitesLock

  let
    env = loadPrologueEnv(".env")
    settings = newSettings(
      appName = "It's Up",
      debug = false,
      port = Port(env.getOrDefault("port", 8080))
    )

  var app = newApp(settings = settings)
  app.get("/{id}", check)
  run app

  deinitLock sitesLock


when isMainModule:
  import pkg/cligen
  dispatch itsup
