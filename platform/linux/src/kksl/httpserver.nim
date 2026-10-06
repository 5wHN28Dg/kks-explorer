# A copy of Nim 2.2.12's std/asynchttpserver (lib/pure/asynchttpserver.nim, (c) 2015 Dominik Picheta, MIT, Nim's
# copying.txt), with limits for a server that faces the plant network directly (issue #27, advisory
# GHSA-xfj6-p785-whg5). The changes, all marked "kks:":
# - a request with any Transfer-Encoding is refused (411), whatever its method and even with a Content-Length: the
#   stdlib read chunked POST bodies with no size limit before the application saw the request, and left other
#   methods' bodies on the socket to be read as the next request. No Walkdown client sends one;
# - deadlines: the request line within IdleTimeoutMs (a kept-alive connection waits that long), all headers together
#   within HeaderTimeoutMs, a Content-Length body within BodyTimeoutMs (read in pieces as it arrives), and the
#   handler with its answer within ResponseTimeoutMs;
# - a malformed request line, a bad or second Content-Length, or a header name with spaces is answered and the
#   connection closed; all headers together at most MaxHeaderBytes and MaxHeaders;
# - at most MaxConnections connections at a time, and MaxPerAddress from one address.
# Everything else is the stdlib's code. Re-check against the stdlib at each Nim upgrade.
#
#
#            Nim's Runtime Library
#        (c) Copyright 2015 Dominik Picheta
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module implements a high performance asynchronous HTTP server.
##
## (kks: the stdlib's note says to put a reverse proxy in front in production; Walkdown's listener takes only
## this machine's addresses (issue #26), and the limits above stand either way.)

import std/[asyncnet, asyncdispatch, parseutils, uri, strutils, tables, times]
import std/httpcore
from std/nativesockets import getLocalAddr, Domain, AF_INET, AF_INET6
import std/private/since

when defined(nimPreviewSlimSystem):
  import std/assertions

export httpcore except parseHeader

const
  maxLine = 8*1024
  HeaderTimeoutMs* = 20_000     ## kks: all the headers together, from the request line on
  IdleTimeoutMs* = 60_000       ## kks: waiting for the next request on a kept-alive connection
  BodyTimeoutMs* = 300_000      ## kks: a Content-Length body (uploads are at most a few tens of MB)
  MaxConnections* = 512         ## kks
  MaxPerAddress* = 64           ## kks
  MaxHeaderBytes* = 64 * 1024   ## kks: all header lines of one request together
  MaxHeaders* = 100             ## kks
  MaxBodiesInFlight* = 256 * 1024 * 1024   ## kks: bodies read at once before any handler sees them (503 beyond)
  ResponseTimeoutMs* = 120_000  ## kks: the handler and sending its response (a client that never reads)

# TODO: If it turns out that the decisions that asynchttpserver makes
# explicitly, about whether to close the client sockets or upgrade them are
# wrong, then add a return value which determines what to do for the callback.
# Also, maybe move `client` out of `Request` object and into the args for
# the proc.
type
  Request* = object
    client*: AsyncSocket # TODO: Separate this into a Response object?
    reqMethod*: HttpMethod
    headers*: HttpHeaders
    protocol*: tuple[orig: string, major, minor: int]
    url*: Uri
    hostname*: string    ## The hostname of the client that made the request.
    body*: string

  AsyncHttpServer* = ref object
    socket: AsyncSocket
    reuseAddr: bool
    reusePort: bool
    maxBody: int ## The maximum content-length that will be read for the body.
    maxFDs: int
    open: int                   ## kks: connections now
    perAddress: Table[string, int]   ## kks
    bodyBytes: int              ## kks: request bodies being read now, all connections together

proc getPort*(self: AsyncHttpServer): Port {.since: (1, 5, 1).} =
  ## Returns the port `self` was bound to.
  ##
  ## Useful for identifying what port `self` is bound to, if it
  ## was chosen automatically, for example via `listen(Port(0))`.
  runnableExamples:
    from std/nativesockets import Port
    let server = newAsyncHttpServer()
    server.listen(Port(0))
    assert server.getPort.uint16 > 0
    server.close()
  result = getLocalAddr(self.socket)[1]

proc newAsyncHttpServer*(reuseAddr = true, reusePort = false,
                         maxBody = 8388608): AsyncHttpServer =
  ## Creates a new `AsyncHttpServer` instance.
  result = AsyncHttpServer(reuseAddr: reuseAddr, reusePort: reusePort, maxBody: maxBody)

proc addHeaders(msg: var string, headers: HttpHeaders) =
  for k, v in headers:
    msg.add(k & ": " & v & "\c\L")

proc sendHeaders*(req: Request, headers: HttpHeaders): Future[void] =
  ## Sends the specified headers to the requesting client.
  var msg = ""
  addHeaders(msg, headers)
  return req.client.send(msg)

proc respond*(req: Request, code: HttpCode, content: string,
              headers: HttpHeaders = nil): Future[void] =
  ## Responds to the request with the specified `HttpCode`, headers and
  ## content.
  ##
  ## This procedure will **not** close the client socket.
  ##
  ## Example:
  ##   ```Nim
  ##   import std/json
  ##   proc handler(req: Request) {.async.} =
  ##     if req.url.path == "/hello-world":
  ##       let msg = %* {"message": "Hello World"}
  ##       let headers = newHttpHeaders([("Content-Type","application/json")])
  ##       await req.respond(Http200, $msg, headers)
  ##     else:
  ##       await req.respond(Http404, "Not Found")
  ##   ```
  var msg = "HTTP/1.1 " & $code & "\c\L"

  if headers != nil:
    msg.addHeaders(headers)

  # If the headers did not contain a Content-Length use our own
  if headers.isNil() or not headers.hasKey("Content-Length"):
    msg.add("Content-Length: ")
    # this particular way saves allocations:
    msg.addInt content.len
    msg.add "\c\L"

  msg.add "\c\L"
  msg.add(content)
  result = req.client.send(msg)

proc respondError(req: Request, code: HttpCode): Future[void] =
  ## Responds to the request with the specified `HttpCode`.
  let content = $code
  var msg = "HTTP/1.1 " & content & "\c\L"

  msg.add("Content-Length: " & $content.len & "\c\L\c\L")
  msg.add(content)
  result = req.client.send(msg)

type Alarm = ref object
  ## kks: one per connection, firing when `deadline` passes. withTimeout made a timer per read that lived until it
  ## expired, so a client sending many short lines filled memory with timers (1 GB in seconds).
  deadline: float
  fired: Future[void]
  done: bool

proc newAlarm(): Alarm = Alarm(fired: newFuture[void]("kks.alarm"))

proc watch(a: Alarm) {.async.} =
  while not a.done:
    await sleepAsync(500)
    if not a.done and epochTime() >= a.deadline and not a.fired.finished: a.fired.complete()

proc within[T](a: Alarm, client: AsyncSocket, f: Future[T], deadline: float): Future[bool] {.async.} =
  ## kks: false (and the connection closed) when `f` doesn't finish before `deadline` (epoch seconds)
  if epochTime() >= deadline:
    client.close(); return false
  a.deadline = deadline
  await (f or a.fired)
  a.fired.clearCallbacks()
  if f.finished: return true
  client.close()
  return false

proc parseProtocol(protocol: string): tuple[orig: string, major, minor: int] =
  result = default(tuple[orig: string, major, minor: int])
  var i = protocol.skipIgnoreCase("HTTP/")
  if i != 5:
    raise newException(ValueError, "Invalid request protocol. Got: " &
        protocol)
  result.orig = protocol
  i.inc protocol.parseSaturatedNatural(result.major, i)
  if i < protocol.len: inc i # Skip .
  i.inc protocol.parseSaturatedNatural(result.minor, i)

proc sendStatus(client: AsyncSocket, status: string): Future[void] =
  client.send("HTTP/1.1 " & status & "\c\L\c\L")

proc processRequest(
  server: AsyncHttpServer,
  req: FutureVar[Request],
  client: AsyncSocket,
  address: sink string,
  lineFut: FutureVar[string],
  callback: proc (request: Request): Future[void] {.closure, gcsafe.},
  alarm: Alarm,
): Future[bool] {.async.} =

  # Alias `request` to `req.mget()` so we don't have to write `mget` everywhere.
  template request(): Request =
    req.mget()

  # GET /path HTTP/1.1
  # Header: val
  # \n
  request.headers.clear()
  request.body = ""
  when defined(gcArc) or defined(gcOrc) or defined(gcAtomicArc):
    request.hostname = address
  else:
    request.hostname.shallowCopy(address)
  assert client != nil
  request.client = client

  # We should skip at least one empty line before the request
  # https://tools.ietf.org/html/rfc7230#section-3.5
  for i in 0..1:
    lineFut.mget().setLen(0)
    lineFut.clean()
    if not await alarm.within(client, client.recvLineInto(lineFut, maxLength = maxLine), epochTime() + IdleTimeoutMs / 1000):   # kks
      return false

    if lineFut.mget == "":
      client.close()
      return false

    if lineFut.mget.len > maxLine:
      await request.respondError(Http413)
      client.close()
      return false
    if lineFut.mget != "\c\L":
      break

  # First line - GET /path HTTP/1.1
  var i = 0
  for linePart in lineFut.mget.split(' '):
    case i
    of 0:
      case linePart
      of "GET": request.reqMethod = HttpGet
      of "POST": request.reqMethod = HttpPost
      of "HEAD": request.reqMethod = HttpHead
      of "PUT": request.reqMethod = HttpPut
      of "DELETE": request.reqMethod = HttpDelete
      of "PATCH": request.reqMethod = HttpPatch
      of "OPTIONS": request.reqMethod = HttpOptions
      of "CONNECT": request.reqMethod = HttpConnect
      of "TRACE": request.reqMethod = HttpTrace
      else:
        await request.respondError(Http400)   # kks: answered, then closed (queued answers to a stream of bad
        client.close()                        # lines grew without limit)
        return false
    of 1:
      try:
        parseUri(linePart, request.url)
      except ValueError:
        await request.respondError(Http400)   # kks
        client.close()
        return false
    of 2:
      try:
        request.protocol = parseProtocol(linePart)
      except ValueError:
        await request.respondError(Http400)   # kks
        client.close()
        return false
    else:
      await request.respondError(Http400)   # kks
      client.close()
      return false
    inc i
  if i != 3:   # kks: method, target and protocol, nothing less (the previous request's values stayed otherwise)
    await request.respondError(Http400)
    client.close()
    return false

  # Headers
  let headerDeadline = epochTime() + HeaderTimeoutMs / 1000   # kks: one deadline for all of them
  var headerBytes = 0                                         # kks
  while true:
    i = 0
    lineFut.mget.setLen(0)
    lineFut.clean()
    if not await alarm.within(client, client.recvLineInto(lineFut, maxLength = maxLine), headerDeadline):   # kks
      client.close()
      return false

    if lineFut.mget == "":
      client.close(); return false
    if lineFut.mget.len > maxLine:
      await request.respondError(Http413)
      client.close(); return false
    if lineFut.mget == "\c\L": break
    headerBytes += lineFut.mget.len                               # kks: size and count of all headers
    if headerBytes > MaxHeaderBytes or request.headers.len >= MaxHeaders:
      await client.sendStatus("431 Request Header Fields Too Large")
      client.close(); return false
    if ':' notin lineFut.mget or (lineFut.mget.toLowerAscii.startsWith("content-length") and ',' in lineFut.mget):   # kks
      await client.sendStatus("400 Bad Request")
      client.close(); return false
    let (key, value) = parseHeader(lineFut.mget)
    # kks: a name with spaces ("Transfer-Encoding : chunked") or a second Content-Length would be read differently
    # by a proxy in front; refuse both.
    if key.len == 0 or key != key.strip or ' ' in key or '\t' in key or
       (cmpIgnoreCase(key, "Content-Length") == 0 and request.headers.hasKey("Content-Length")):
      await client.sendStatus("400 Bad Request")
      client.close(); return false
    request.headers[key] = value
    # Ensure the client isn't trying to DoS us.
    if request.headers.len > headerLimit:
      await client.sendStatus("400 Bad Request")
      request.client.close()
      return false

  if request.reqMethod == HttpPost:
    # Check for Expect header
    if request.headers.hasKey("Expect"):
      if "100-continue" in request.headers["Expect"]:
        await client.sendStatus("100 Continue")
      else:
        await client.sendStatus("417 Expectation Failed")   # kks: and nothing more on this connection
        client.close()
        return false

  # Read the body
  if request.headers.hasKey("Transfer-Encoding"):
    # kks: refused, any method, with or without Content-Length (finding #27). The stdlib read chunked POST bodies
    # with no size limit before the callback ran, and left other methods' bodies on the socket.
    await request.respond(Http411, "Transfer-Encoding is not accepted; send Content-Length.")
    client.close()
    return false
  # - Check for Content-length header
  if request.headers.hasKey("Content-Length"):
    var contentLength = 0
    let cl = request.headers["Content-Length"]
    if seq[string](request.headers.getOrDefault("Content-Length")).len != 1:   # kks: "5, 7" splits into two values
      await request.respond(Http400, "Bad Request. Invalid Content-Length.")
      client.close()
      return false
    # kks: digits only ("5abc" and "5, 7" read as 5 before), and a bad one closes the connection
    if cl.len == 0 or cl.len > 12 or not cl.allCharsInSet(Digits) or parseSaturatedNatural(cl, contentLength) == 0:
      await request.respond(Http400, "Bad Request. Invalid Content-Length.")
      client.close()
      return false
    else:
      if contentLength > server.maxBody:
        await request.respondError(Http413)
        client.close()
        return false
      # kks: read in pieces as they arrive (recv(n) allocated all n bytes before reading any), within a deadline
      if server.bodyBytes + contentLength > MaxBodiesInFlight:   # kks: all connections' bodies together
        await request.respond(Http503, "Too many uploads at once; try again shortly.")
        client.close()
        return false
      let bodyDeadline = epochTime() + BodyTimeoutMs / 1000
      var body = ""
      server.bodyBytes += contentLength
      try:
        while body.len < contentLength:
          let part = client.recv(min(64 * 1024, contentLength - body.len))
          if not await alarm.within(client, part, bodyDeadline):
            return false
          let got = part.read
          if got.len == 0: break
          body.add got
      finally:
        server.bodyBytes -= contentLength
      request.body = body
      if request.body.len != contentLength:
        await request.respond(Http400, "Bad Request. Content-Length does not match actual.")
        client.close()
        return false
  elif request.reqMethod == HttpPost:
    await request.respond(Http411, "Content-Length required.")
    return true

  # Call the user's callback.
  let handled = callback(request)   # kks: with a deadline, so a client that never reads its answer lets go
  if not await alarm.within(client, handled, epochTime() + ResponseTimeoutMs / 1000):
    return false
  if handled.failed: raise handled.readError

  if "upgrade" in request.headers.getOrDefault("connection"):
    return false

  # The request has been served, from this point on returning `true` means the
  # connection will not be closed and will be kept in the connection pool.

  # Persistent connections
  if (request.protocol == HttpVer11 and
      cmpIgnoreCase(request.headers.getOrDefault("connection"), "close") != 0) or
     (request.protocol == HttpVer10 and
      cmpIgnoreCase(request.headers.getOrDefault("connection"), "keep-alive") == 0):
    # In HTTP 1.1 we assume that connection is persistent. Unless connection
    # header states otherwise.
    # In HTTP 1.0 we assume that the connection should not be persistent.
    # Unless the connection header states otherwise.
    return true
  else:
    request.client.close()
    return false

proc processClient(server: AsyncHttpServer, client: AsyncSocket, address: string,
                   callback: proc (request: Request):
                      Future[void] {.closure, gcsafe.}) {.async.} =
  var request = newFutureVar[Request]("asynchttpserver.processClient")
  request.mget().url = initUri()
  request.mget().headers = newHttpHeaders()
  var lineFut = newFutureVar[string]("asynchttpserver.processClient")
  lineFut.mget() = newStringOfCap(80)

  let alarm = newAlarm()   # kks
  asyncCheck alarm.watch()
  try:
    while not client.isClosed:
      let retry = await processRequest(
        server, request, client, address, lineFut, callback, alarm
      )
      if not retry:
        client.close()
        break
  finally:   # kks: the connection counts
    alarm.done = true
    dec server.open
    server.perAddress[address] = server.perAddress.getOrDefault(address) - 1
    if server.perAddress[address] <= 0: server.perAddress.del address

const
  nimMaxDescriptorsFallback* {.intdefine.} = 16_000 ## fallback value for \
    ## when `maxDescriptors` is not available.
    ## This can be set on the command line during compilation
    ## via `-d:nimMaxDescriptorsFallback=N`

proc listen*(server: AsyncHttpServer; port: Port; address = ""; domain = AF_INET) =
  ## Listen to the given port and address.
  when declared(maxDescriptors):
    server.maxFDs = try: maxDescriptors() except: nimMaxDescriptorsFallback
  else:
    server.maxFDs = nimMaxDescriptorsFallback
  server.socket = newAsyncSocket(domain)
  if server.reuseAddr:
    server.socket.setSockOpt(OptReuseAddr, true)
  when not defined(nuttx):
    if server.reusePort:
      server.socket.setSockOpt(OptReusePort, true)
  server.socket.bindAddr(port, address)
  server.socket.listen()

proc shouldAcceptRequest*(server: AsyncHttpServer;
                          assumedDescriptorsPerRequest = 5): bool {.inline.} =
  ## Returns true if the process's current number of opened file
  ## descriptors is still within the maximum limit and so it's reasonable to
  ## accept yet another request.
  result = assumedDescriptorsPerRequest < 0 or
    (activeDescriptors() + assumedDescriptorsPerRequest < server.maxFDs)

proc admit(server: AsyncHttpServer, client: AsyncSocket, address: string,
           callback: proc (request: Request): Future[void] {.closure, gcsafe.}) =
  ## kks: the connection caps; processClient gives the slot back when the connection ends
  if server.open >= MaxConnections or server.perAddress.getOrDefault(address) >= MaxPerAddress:
    client.close()
    return
  inc server.open
  server.perAddress.mgetOrPut(address, 0) += 1
  asyncCheck processClient(server, client, address, callback)

proc openConnections*(server: AsyncHttpServer): int = server.open   ## kks: for tests and diagnostics

proc acceptRequest*(server: AsyncHttpServer,
            callback: proc (request: Request): Future[void] {.closure, gcsafe.}) {.async.} =
  ## Accepts a single request. Write an explicit loop around this proc so that
  ## errors can be handled properly.
  var (address, client) = await server.socket.acceptAddr()
  server.admit(client, address, callback)

proc serve*(server: AsyncHttpServer, port: Port,
            callback: proc (request: Request): Future[void] {.closure, gcsafe.},
            address = "";
            assumedDescriptorsPerRequest = -1;
            domain = AF_INET) {.async.} =
  ## Starts the process of listening for incoming HTTP connections on the
  ## specified address and port.
  ##
  ## When a request is made by a client the specified callback will be called.
  ##
  ## If `assumedDescriptorsPerRequest` is 0 or greater the server cares about
  ## the process's maximum file descriptor limit. It then ensures that the
  ## process still has the resources for `assumedDescriptorsPerRequest`
  ## file descriptors before accepting a connection.
  ##
  ## You should prefer to call `acceptRequest` instead with a custom server
  ## loop so that you're in control over the error handling and logging.
  listen server, port, address, domain
  while true:
    if shouldAcceptRequest(server, assumedDescriptorsPerRequest):
      var (address, client) = await server.socket.acceptAddr()
      server.admit(client, address, callback)
    else:
      poll()
    #echo(f.isNil)
    #echo(f.repr)

proc close*(server: AsyncHttpServer) =
  ## Terminates the async http server instance.
  server.socket.close()
