require 'rack/auth/abstract/handler'
require 'rack/auth/abstract/request'
require 'rack/auth/basic'
require 'open-uri'

class RedmineGrackAuth < Rack::Auth::Basic

  def valid?(auth)
    url = $grackConfig[:redmine]
    return false if !url

    url = $grackConfig[:require_ssl_for_auth] ? 'https://' + url : 'http://' + url

    creds = *auth.credentials
    user, pass = creds[0, 2]

    identifier = get_project
    return false if !identifier
    permission = (@req.request_method == "POST" && Regexp.new("(.*?)/git-receive-pack$").match(@req.path_info) ? 'rw' : 'r')

    begin
      open("#{url}/grack/xml/#{identifier}/#{permission}", :http_basic_authentication => [user, pass]) do |f|
        f.each do |line|
          return false if not line == "OK"
        end
      end
    rescue
      return false
    end

    return true
  end

  def call(env)
    @env = env  
    @req = Rack::Request.new(env)

    return [500, {}, "Configuration error"] if(not defined?($grackConfig))
    return [403, {}, "Require https"] if($grackConfig[:require_ssl_for_auth] && @req.scheme != "https")

    auth = Request.new(env)
    return unauthorized unless auth.provided?
    return bad_request unless auth.basic?
    return [403, {}, "Authentication failed"] unless valid?(auth)

    env['REMOTE_USER'] = auth.username
    return @app.call(env)
  end

  def get_project
    paths = ["(.*?)/git-upload-pack$", "(.*?)/git-receive-pack$", "(.*?)/info/refs$", "(.*?)/HEAD$", "(.*?)/objects" ]

    paths.each do |re|
      if m = Regexp.new(re).match(@req.path)
        identifier = m[1].match(/^\/([-\w]+)(?:\.git)?$/)[1]
        return ((not identifier or identifier.empty?) ? nil : identifier)
      end
    end

    return nil
  end

end
