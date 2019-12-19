--
-- Cybermon utility, to output JSON model data.
-- 

-- This file is a module, so you need to create a table, which will be
-- returned to the calling environment.  It doesn't matter what you call it.
local module = {}

-- Other modules -----------------------------------------------------------

local mime = require("mime")
local json = require("json")
local os = require("os")
local dns = require("util.dns")

-- Initialise UUID ---------------------------------------------------------

-- Needed to help initialise UUID.
local uuid = require("uuid")
local string = require("string")

local socket = require "socket"
local sha1 = require 'sha1'
local bit32 = require 'bit32'
local timeMS = socket.gettime()*1000
local hostname = io.popen("uname -n"):read()
local seedInput = hostname .. timeMS

-- seed only excepts 32 bit numbers, so hash the input and extract last 32 bits
local seedData = string.sub(sha1.binary(seedInput) , -4,-1)
local seed = string.byte(seedData,4)
seed = seed + bit32.lshift(string.byte(seedData,3),8)
seed = seed + bit32.lshift(string.byte(seedData,2),16)
seed = seed + bit32.lshift(string.byte(seedData,1),24)

uuid.randomseed(seed)

-- Initialise, register a submit function. ---------------------------------
local submit
module.init = function(s)
  submit = s
end

-- Base64 encoding
local b64 = function(x)
  local a, b = mime.b64(x)
  if (a == nil) then
    return ""
  end
  return a
end

-- hex encoding
local str_to_hex = function(x)
  return "0x" .. x:gsub('.', function (c)
      return string.format('%02X', string.byte(c))
    end)
end

local int_to_hex = function(x)
  return "0x" .. string.format('%x', x)
end

-- Gets the stack of addresses on the src/dest side of a context.
local function get_stack(context, addrs, is_src)

  local par = context:get_parent()

  if par then
    get_stack(par, addrs, is_src)
  end

  local cls, addr
  if is_src then
    cls, addr = context:get_src_addr()
  else
    cls, addr = context:get_dest_addr()
  end

  if cls == "root" then
    return
  end

  if addr == "" then
    table.insert(addrs, cls)
  else
    table.insert(addrs, cls .. ":" .. addr)
  end
  
end

-- Initialise a basic observation
local initialise_observation = function(e, indicators)

  local obs = {}
  obs["device"] = e.device

  net, src, dest = e.context:get_network_info()
  if not(net == "") then
    obs["network"] = net
  end

  local addrs = {}
  get_stack(e.context, addrs, true)
  obs["src"] = addrs

  addrs = {}
  get_stack(e.context, addrs, false)
  obs["dest"] = addrs

  dir = e.context:get_direction()
  if dir == "FROM_DEVICE" then
    obs["origin"] = "device"
  else
    if dir == "TO_DEVICE" then
      obs["origin"] = "network"
    end
  end
  
  if indicators and not(#indicators == 0) then
    obs["indicators"] = {}
    obs["indicators"]["on"] = {}
    obs["indicators"]["description"] = {}
    obs["indicators"]["value"] = {}
    obs["indicators"]["id"] = {}
    for key, value in pairs(indicators) do
      table.insert(obs["indicators"]["on"], value["on"])
      table.insert(obs["indicators"]["description"], value["description"])
      table.insert(obs["indicators"]["value"], value["value"])
      table.insert(obs["indicators"]["id"], value["id"])
    end
  end

  obs["time"] = e.time
  obs["id"] = uuid()

  return obs

end

module.initialise_observation = initialise_observation

-- This function is called when a trigger events starts collection of an
-- attacker. device=the trigger ID, addr=trigger address
module.trigger_up = function(e)
end

-- This function is called when an attacker goes off the air
module.trigger_down = function(e)
end

-- This function is called when a stream-orientated connection is made
-- (e.g. TCP)
module.connection_up = function(e)
  local obs = initialise_observation(e)
  obs["action"] = "connected_up"
  submit(obs)
end

-- This function is called when a stream-orientated connection is closed
module.connection_down = function(e)
  local obs = initialise_observation(e)
  obs["action"] = "connected_down"
  submit(obs)
end

-- This function is called when a datagram is observed, but the protocol
-- is not recognised.
module.unrecognised_datagram = function(e)
  local obs = initialise_observation(e)
  obs["action"] = "unrecognised_datagram"
  obs["unrecognised_datagram"] = {}
  obs["unrecognised_datagram"]["payload"] = b64(e.data)
  submit(obs)
end

-- This function is called when stream data  is observed, but the protocol
-- is not recognised.
module.unrecognised_stream = function(e)
  local obs = initialise_observation(e)
  obs["action"] = "unrecognised_stream"
  obs["unrecognised_stream"] = {}
  obs["unrecognised_stream"]["payload"] = b64(e.data)
  obs["unrecognised_stream"]["position"] = e.position
  submit(obs)
end

-- This function is called when an ICMP message is observed.
module.icmp = function(e)
  local obs = initialise_observation(e)
  obs["action"] = "icmp"
  obs["icmp"] = { type=e.type, code=e.code, payload=b64(e.data) }
  submit(obs)
end

-- This function is called when an HTTP request is observed.
module.http_request = function(e)
  local obs = initialise_observation(e)
  obs["action"] = "http_request"
  obs["url"] = e.url
  obs["http_request"] = { method=e.method, header=e.header }
  if not(e.body == "") then
    obs["http_request"]["body"] = b64(e.body)
  end
  submit(obs)
end

-- This function is called when an HTTP response is observed.
module.http_response = function(e)
  local obs = initialise_observation(e)
  obs["action"] = "http_response"
  obs["url"] = e.url
  obs["http_response"] = {}
  obs["http_response"]["code"] = e.code
  obs["http_response"]["status"] = e.status
  obs["http_response"]["header"] = e.header
  obs["http_response"]["body"] = b64(e.body)
  submit(obs)
end

-- This function is called when a DNS message is observed.
module.dns_message = function(e)

  local obs = initialise_observation(e)

  obs["action"] = "dns_message"
  obs["dns_message"] = {}

  if e.header.qr == 0 then
    obs["dns_message"]["type"] = "query"
  else
    obs["dns_message"]["type"] = "response"
  end

  local q = {}
  json.util.InitArray(q)
  for key, value in pairs(e.queries) do
    local a = {}
    a["name"] = value.name
    if dns.type_name[value.type] == nil then
      a["type"] = tostring(value.type)
    else
      a["type"] = dns.type_name[value.type]
    end
    a["class"] = dns.class_name[value.class]
    q[#q + 1] = a
  end
  obs["dns_message"]["query"] = q

  q = {}
  json.util.InitArray(q)
  for key, value in pairs(e.answers) do
    local a = {}
    a["name"] = value.name
    if dns.type_name[value.type] == nil then
      a["type"] = tostring(value.type)
    else
      a["type"] = dns.type_name[value.type]
    end
    a["class"] = dns.class_name[value.class]
    if value.rdaddress then
       a["address"] = value.rdaddress
    end
    if value.rdname then
       a["name"] = value.rdname
    end
    q[#q + 1] = a
  end
  obs["dns_message"]["answer"] = q
  submit(obs)
end

-- This function is called when an FTP command is observed.
module.ftp_command = function(e)
  local obs = initialise_observation(e)
  obs["action"] = "ftp_command"
  obs["ftp_command"] = { command=e.command }
  submit(obs)
end

-- This function is called when an FTP response is observed.
module.ftp_response = function(e)
  local obs = initialise_observation(e)
  obs["action"] = "ftp_response"
  obs["ftp_response"] = { status=e.status, text=e.text }
  submit(obs)
end

-- This function is called when a SIP request message is observed.
module.sip_request = function(e)
  local obs = initialise_observation(e)
  obs["action"] = "sip_request"
  obs["sip_request"] = { method=e.method, from=e.from, to=e.to, body=e.data,
  	payload=b64(e.data) }
end

-- This function is called when a SIP response message is observed.
module.sip_response = function(e)
  local obs = initialise_observation(e)
  obs["action"] = "sip_response"
  obs["sip_response"] = { code=e.code, status=e.status, from=e.from, to=e.to,
  	payload=b64(e.data) }
  submit(obs)
end

-- This function is called when a SIP SSL message is observed.
module.sip_ssl = function(e)
  local obs = initialise_observation(e)
  obs["action"] = "sip_ssl"
  obs["sip_ssl"] = { payload=b64(e.data) }
  submit(obs)
end

-- This function is called when an IMAP message is observed.
module.rtp = function(e)
  local obs = initialise_observation(e)
  obs["action"] = "rtp"
  obs["rtp"] = { payload=b64(e.data) }
  submit(obs)
end

-- This function is called when an IMAP message is observed.
module.rtp_ssl = function(e)
  local obs = initialise_observation(e)
  obs["action"] = "rtp_ssl"
  obs["rtp_ssl"] = { payload=b64(e.data) }
  submit(obs)
end

-- This function is called when an IMAP message is observed.
module.imap = function(e)
  local obs = initialise_observation(e)
  obs["action"] = "imap"
  obs["imap"] = { payload=b64(e.data) }
  submit(obs)
end

-- This function is called when an IMAP SSL message is observed.
module.imap_ssl = function(e)
  local obs = initialise_observation(e)
  obs["action"] = "imap_ssl"
  obs["imap_ssl"] = { payload=b64(e.data) }
  submit(obs)
end

-- This function is called when a POP3 message is observed.
module.pop3 = function(e)
  local obs = initialise_observation(e)
  obs["action"] = "pop3"
  obs["pop3"] = { payload=b64(e.data) }
  submit(obs)
end

-- This function is called when a POP3 SSL message is observed.
module.pop3_ssl = function(e)
  local obs = initialise_observation(e)
  obs["action"] = "pop3_ssl"
  obs["pop3_ssl"] = { payload=b64(e.data) }
  submit(obs)
end

-- This function is called when an SMTP command is observed.
module.smtp_command = function(e)
  local obs = initialise_observation(e)
  obs["action"] = "smtp_command"
  obs["smtp_command"] = { command=e.command }
  submit(obs)
end

-- This function is called when an SMTP response is observed.
module.smtp_response = function(e)
  local obs = initialise_observation(e)
  obs["action"] = "smtp_response"
  obs["smtp_response"] = { status=e.status, text=e.text }
  submit(obs)
end

-- This function is called when an SMTP response is observed.
module.smtp_data = function(e)
  local obs = initialise_observation(e)
  obs["action"] = "smtp_data"
  obs["smtp_data"] = { from=e.from, to=e.to, body=e.data }
  submit(obs)
end

-- This function is called when a NTP timestamp message is observed.
module.ntp_timestamp_message = function(e)
  local obs = initialise_observation(e)
  obs["action"] = "ntp_timestamp"
  obs["ntp_timestamp"] = { version=e.header.version, mode=e.header.mode }
  submit(obs)
end

-- This function is called when a NTP control message is observed.
module.ntp_control_message = function(e)
  local obs = initialise_observation(e)
  obs["action"] = "ntp_control"
  obs["ntp_control"] = { version=e.header.version, mode=e.header.mode }
  submit(obs)
end

-- This function is called when an NTP private message is observed.
module.ntp_private_message = function(e)
  local obs = initialise_observation(e)
  obs["action"] = "ntp_private"
  obs["ntp_private"] = { version=e.header.version, mode=e.header.mode }
  submit(obs)
end

-- This function is called when a gre message is observed.
module.gre = function(e)
  local obs = initialise_observation(e)
  obs["action"] = "gre"
  obs["gre"] = { next_proto=e.next_proto, payload=b64(e.payload) }

  if e.key ~= 0 then
    obs["gre"]["key"] = tostring(e.key)
  end
  if e.sequence_number ~= 0 then
    obs["gre"]["sequence_number"] = tostring(e.sequence_number)
  end
  submit(obs)
end

-- This function is called when a gre message is observed.
module.gre_pptp = function(e)
  local obs = initialise_observation(e)
  obs["action"] = "gre_pptp"
  obs["gre_pptp"] = { next_proto=e.next_proto, call_id=e.call_id,
    payload_length=e.payload_length, payload=b64(e.payload) }

  if e.sequence_number ~= 0 then
    obs["gre_pptp"]["sequence_number"] = tostring(e.sequence_number)
  end
  if e.acknowledgement_number ~= 0 then
    obs["gre_pptp"]["acknowledgement_number"] = tostring(e.acknowledgement_number)
  end
  submit(obs)
end

-- This function is called when an esp packet is observed.
module.esp = function(e)
  local obs = initialise_observation(e)
  obs["action"] = "esp"
  obs["esp"] = { spi=e.spi, sequence_number=e.sequence_number,
    payload_length=e.payload_length }

  -- the payload is available to be output, but it is encrypted so not a lot of use
  -- obs["esp"]["payload"] = b64(e.payload)
  submit(obs)
end

-- This function is called when an ip packet with an unprocessed next protocol is observed.
module.unrecognised_ip_protocol = function(e)
  local obs = initialise_observation(e)
  obs["action"] = "unrecognised_ip_protocol"
  obs["unrecognised_ip_protocol"] = { next_proto=e.next_proto, payload_length=e.payload_length,
    payload=b64(e.payload)}
  submit(obs)
end

-- This function is called when a 802.11 packet is observed.
module.wlan = function(e)
  local obs = initialise_observation(e)
  obs["action"] = "802.11"
  obs["802.11"] = { version=e.version, type=e.type, subtype=e.subtype, flags=e.flags,
    protected=e.protected, filt_addr=e.filt_addr, frag_num=e.frag_num, seq_num=e.seq_num,
    duration=e.duration}
  submit(obs)
end

-- This function is called when an unknown tls packet is observed and surveyed.
module.tls_unknown = function(e)
  local obs = initialise_observation(e)
  obs["action"] = "tls_unknown"
  obs["tls_unknown"] = {tls={ version=e.version, content_type=e.content_type, length=e.length}}
  submit(obs)
end

-- This function is called when a tls client hello packet is observed.
module.tls_client_hello = function(e)
  local obs = initialise_observation(e)
  obs["action"] = "tls_client_hello"
  tls = { version=e.version, session_id=e.session_id}
  tls["random"] = {timestamp=e.random_timestamp, data=str_to_hex(e.random_data)}

  cs = {}
  json.util.InitArray(cs)
  for key, value in pairs(e.cipher_suites) do
    -- key is just the index
    -- the id is available in the value too if needed (only used for unassigned currently)
    local val = ""
    if value.name == "Unassigned" then
      val = value.name .. " - " .. int_to_hex(value.id)
    else
      val = value.name
    end
    cs[#cs + 1] = val
  end
  tls["cipher_suites"] = cs

  cm = {}
  json.util.InitArray(cm)
  for key, value in pairs(e.compression_methods) do
    -- key is just the index
    -- the id is available in the value too if needed (only used for unassigned currently)
    local val = ""
    if value.name == "Unassigned" then
      val = value.name .. " - " .. int_to_hex(value.id)
    else
      val = value.name
    end
    cm[#cm + 1] = val
  end
  tls["compression_methods"] = cm

  exts = {}
  json.util.InitArray(exts)
  for key, value in pairs(e.extensions) do
    -- key is just the index
    -- the id is available in the value too if needed (only used for unassigned currently)
    ext = {}
    ext["length"] = value.length
    if string.len(value.data) > 0 then
      ext["data"] = str_to_hex(value.data)
    end
    if value.name == "Unassigned" then
      ext["name"] = value.name .. " - " .. int_to_hex(value.type)
    else
      ext["name"] = value.name
    end
    exts[#exts + 1] = ext
  end
  tls["extensions"] = exts
  obs["tls_client_hello"] = {tls=tls}
  submit(obs)
end

-- This function is called when a tls client hello packet is observed.
module.tls_server_hello = function(e)
  local obs = initialise_observation(e)
  obs["action"] = "tls_server_hello"
  tls = { version=e.version, session_id=e.session_id}
  tls["random"] = {timestamp=e.random_timestamp, data=str_to_hex(e.random_data)}

  -- the id is available too if needed (only used for unassigned currently)
  local cipherName = ""
  if e.cipher_suite.name == "Unassigned" then
    cipherName = e.cipher_suite.name .. " - " .. int_to_hex(e.cipher_suite.id)
  else
    cipherName = e.cipher_suite.name
  end
  tls["cipher_suite"] = cipherName

  -- the id is available in the value too if needed (only used for unassigned currently)
  local compressionName = ""
  if e.compression_method.name == "Unassigned" then
    compressionName = e.compression_method.name .. " - " .. int_to_hex(e.compression_method.id)
  else
    compressionName = e.compression_method.name
  end
  tls["compression_method"] = compressionName

  exts = {}
  json.util.InitArray(exts)
  for key, value in pairs(e.extensions) do
    -- key is just the index
    -- the id is available in the value too if needed (only used for unassigned currently)
    ext = {}
    ext["length"] = value.length
    if string.len(value.data) > 0 then
      ext["data"] = str_to_hex(value.data)
    end
    if value.name == "Unassigned" then
      ext["name"] = value.name .. " - " .. int_to_hex(value.type)
    else
      ext["name"] = value.name
    end
    exts[#exts + 1] = ext
  end
  tls["extensions"] = exts
  obs["tls_server_hello"] = {tls=tls}
  submit(obs)
end

-- This function is called when a tls client hello packet is observed.
module.tls_certificates = function(e)
  local obs = initialise_observation(e)
  obs["action"] = "tls_certificates"
  tls = {}
  certs = {}
  json.util.InitArray(exts)
  for key, value in pairs(e.certificates) do
    -- key is just the index
    certs[#certs + 1] = b64(value)
  end
  tls["certificates"] = certs
  obs["tls_certificates"] = {tls=tls}
  submit(obs)
end

-- This function is called when a tls server key exchange packet is observed.
module.tls_server_key_exchange = function(e)
  local obs = initialise_observation(e)
  obs["action"] = "tls_server_key_exchange"
  tls = {key_exchange_algorithm=e.key_exchange_algorithm}

  if e.key_exchange_algorithm == "ec-dh" then
    tls["curve_type"] = e.curve_type
    tls["curve_metadata"] = e.curve_metadata
    tls["public_key"] = b64(e.public_key)
    tls["signature_hash_algorithm"] = e.signature_hash_algorithm
    tls["signature_algorithm"] = e.signature_algorithm
    tls["signature_hash"] = e.signature_hash
  else
    tls["prime"] = str_to_hex(e.prime)
    tls["generator"] = str_to_hex(e.generator)
    tls["pubkey"] = str_to_hex(e.pubkey)
    if e.key_exchange_algorithm == "dh-rsa" then
      tls["signature"] = str_to_hex(e.signature)
    end
  end
  obs["tls_server_key_exchange"] = {tls=tls}
  submit(obs)
end

-- This function is called when a tls server hello done packet is observed.
module.tls_server_hello_done = function(e)
  local obs = initialise_observation(e)
  obs["action"] = "tls_server_hello_done"
  obs["tls_server_hello_done"] = {tls={}}
  submit(obs)
end

-- This function is called when an unknown tls handshake message which isn't explicitly
-- handled is observed.
module.tls_handshake_unknown = function(e)
  local obs = initialise_observation(e)
  obs["action"] = "tls_handshake_unknown"
  obs["tls_handshake_unknown"] = {tls={type=e.type, length=e.length}}
  submit(obs)
end

-- This function is called when a tls certificate request packet is observed.
module.tls_certificate_request = function(e)
  local obs = initialise_observation(e)
  obs["action"] = "tls_certificate_request"
  tls = {cert_types=e.cert_types, signature_algorithms=e.signature_algorithms,
    distinguished_names=str_to_hex(e.distinguished_names)}
  obs["tls_certificate_request"] = {tls=tls}
  submit(obs)
end

-- This function is called when a tls client key exchange is observed.
module.tls_client_key_exchange = function(e)
  local obs = initialise_observation(e)
  obs["action"] = "tls_client_key_exchange"
  obs["tls_client_key_exchange"] = {tls={key=b64(e.key)}}
  submit(obs)
end

-- This function is called when a tls certificate verify packet is observed.
module.tls_certificate_verify = function(e)
  local obs = initialise_observation(e)
  obs["action"] = "tls_certificate_verify"
  tls = {signature_algorithm=e.signature_algorithm,
    signature=e.signature}
  obs["tls_certificate_verify"] = {tls=tls}
  submit(obs)
end

-- This function is called when a tls change cipher spec packet is observed.
module.tls_change_cipher_spec = function(e)
  local obs = initialise_observation(e)
  obs["action"] = "tls_change_cipher_spec"
  obs["tls_change_cipher_spec"] = {tls={value=e.val}}
  submit(obs)
end

-- This function is called when a tls change cipher spec packet is observed.
module.tls_handshake_finished = function(e)
  local obs = initialise_observation(e)
  obs["action"] = "tls_handshake_finished"
  obs["tls_handshake_finished"] = {tls={message=b64(e.msg)}}
  submit(obs)
end

-- This function is called when a tls change cipher spec packet is observed.
module.tls_handshake_complete = function(e)
  local obs = initialise_observation(e)
  obs["action"] = "tls_handshake_complete"
  obs["tls_handshake_complete"] = {tls={}}
  submit(obs)
end

-- This function is called when a tls change cipher spec packet is observed.
module.tls_application_data = function(e)
  local obs = initialise_observation(e)
  obs["action"] = "tls_application_data"
  tls = {version=e.version, length=string.len(e.data)}
  -- the binary data is available but is encrypted so not extracting
  obs["tls_application_data"] = {tls=tls}
  submit(obs)
end

module.event_handlers = {
  trigger_up = module.trigger_up,
  trigger_down = module.trigger_down,
  describe = module.describe,
  connection_up = module.connection_up,
  connection_down = module.connection_down,
  unrecognised_datagram = module.unrecognised_datagram,
  unrecognised_stream = module.unrecognised_stream,
  icmp = module.icmp,
  imap = module.imap,
  imap_ssl = module.imap_ssl,
  pop3 = module.pop3,
  pop3_ssl = module.pop3_ssl,
  rtp = module.rtp,
  rtp_ssl = module.rtp_ssl,
  sip_request = module.sip_request,
  sip_response = module.sip_response,
  sip_ssl = module.sip_ssl,
  smtp_auth = module.smtp_auth,
  http_request = module.http_request,
  http_response = module.http_response,
  smtp_command = module.smtp_command,
  smtp_response = module.smtp_response,
  smtp_data = module.smtp_data,
  dns_message = module.dns_message,
  ftp_command = module.ftp_command,
  ftp_response = module.ftp_response,
  ntp_common = module.ntp_common,
  ntp_timestamp_message = module.ntp_timestamp_message,
  ntp_control_message = module.ntp_control_message,
  ntp_private_message = module.ntp_private_message,
  gre = module.gre,
  grep_pptp = module.grep_pptp,
  esp = module.esp,
  unrecognised_ip_protocol = module.unrecognised_ip_protocol,
  wlan = module.wlan,
  tls_unknown = module.tls_unknown,
  tls_client_hello = module.tls_client_hello,
  tls_server_hello = module.tls_server_hello,
  tls_certificates = module.tls_certificates,
  tls_server_key_exchange = module.tls_server_key_exchange,
  tls_server_hello_done = module.tls_server_hello_done,
  tls_handshake_unknown = module.tls_handshake_unknown,
  tls_certificate_request = module.tls_certificate_request,
  tls_client_key_exchange = module.tls_client_key_exchange,
  tls_certificate_verify = module.tls_certificate_verify,
  tls_change_cipher_spec = module.tls_change_cipher_spec,
  tls_handshake_finished = module.tls_handshake_finished,
  tls_handshake_complete = module.tls_handshake_complete,
  tls_application_data = module.tls_application_data
}

module.event = function(e)
  fn = module.event_handlers[e.action]
  fn(e)
end

-- Return the table
return module
