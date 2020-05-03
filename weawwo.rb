require 'sinatra/base'
require 'config'
require 'octokit'
require 'jira-ruby'
require 'tracker_api'
require 'rest-client'

class WEAWWO < Sinatra::Base
  set :root, File.dirname(__FILE__)
  register Config
  enable :sessions

  def authenticated?
    session[:access_token]
  end
  
  def authenticate!
    erb :index, :locals => {:signed_in => false, :client_id => Settings.github_auth.client_id, :org => Settings.github_auth.required_org}
  end
  
  get '/' do
    if !authenticated?
      authenticate!
    else
      access_token = session[:access_token]
      scopes = []
      begin
        auth_result = RestClient.get('https://api.github.com/user',
          {
            :params => {:access_token => access_token},
            :accept => :json
          })
        
        auth_result = JSON.parse(auth_result)

        auth_result['orgs'] = JSON.parse(RestClient.get(auth_result['organizations_url'],
          {:params => {:access_token => access_token},
          :accept => :json}))

        unless auth_result['orgs'].any? do |o| 
          o != nil && o['login'] != nil && o['login'].upcase == Settings.github_auth.required_org
        end
          raise "user not part of #{Settings.github_auth.required_org}"
        end
      rescue => e
        # request didn't succeed because the token was revoked so we
        # invalidate the token stored in the session and render the
        # index page so that the user can start the OAuth flow again
        puts e
        session[:access_token] = nil
        return authenticate!
      end
  
      sort_by = params[:sort] ? params[:sort].sub('sort-', '').to_sym : :status
      sort_desc = params[:desc] ? params[:desc] == 'true' : false

      issues = Parallel.map([:tracker, :github, :jira], in_threads: 3) { |p| method(p).call }.flatten
      issues = issues.select{|i| i[:status] != 'done'}.sort_by{|i| i[sort_by].to_s.upcase.strip }
      if sort_desc
        issues.reverse!
      end

      erb :index, :locals => {
        :signed_in => true, 
        :issues => issues,
        :sort_by => sort_by,
        :sort_desc => sort_desc,
      }
    end
  end
  
  get '/callback' do
    session_code = request.env['rack.request.query_hash']['code']
  
    result = RestClient.post('https://github.com/login/oauth/access_token',
      {
        :client_id => Settings.github_auth.client_id,
        :client_secret => Settings.github_auth.client_secret,
        :code => session_code
      },
      :accept => :json)
  
    session[:access_token] = JSON.parse(result)['access_token']
  
    redirect '/'
  end
  
  def jira()
    options = {
      :username     => Settings.jira.connection.username,
      :password     => Settings.jira.connection.password,
      :site         => Settings.jira.connection.server,
      :context_path => '',
      :auth_type    => :basic
    }
  
    client = JIRA::Client.new(options)
    issues = client.Issue.jql("PROJECT = \"#{Settings.jira.project}\" AND labels = \"#{Settings.jira.label}\"")
  
    issues.map do |issue|
      state = "open"
      if Settings.jira.states.progress.map{|s| s.upcase }.include?(issue.status.name.upcase)
        state = "progress"
      end
      
      if Settings.jira.states.done.map{|s| s.upcase }.include?(issue.status.name.upcase)
        state = "done"
      end
  
      {
        :title => issue.summary,
        :description => issue.description,
        :status => state,
        :link => "#{Settings.jira.connection.server}/browse/#{issue.key}",
        :source => "jira",
        :assignee => issue.fields[Settings.jira.assigneeCustomField] ? issue.fields[Settings.jira.assigneeCustomField]["displayName"] : "",
      }
    end
  end
  
  def github()
    client = Octokit::Client.new(:access_token => Settings.github.access_token)
    client.auto_paginate = true
    issues = client.issues(Settings.github.project, { :state => 'all', :labels => Settings.github.label })
  
    issues.map do |issue|
      state = "done"
      if issue.state == "open" 
        state = "open"
  
        if (issue.assignee != nil && (issue.assignees.length > 1 || (issue.assignee.login != "#{ Settings.github.default_assignee }")))
          state = "progress"
        end
      end
  
      {
        :title => issue.title,
        :description => issue.body,
        :status => state,
        :link => issue.html_url,
        :source => "github",
        :assignee => issue.assignee ? issue.assignee.login : "",
      }
    end
  end
  
  def tracker()
    client = TrackerApi::Client.new(token: Settings.tracker.access_token)
    project  = client.project(Settings.tracker.project)
    issues = project.stories(filter: "label:\"#{Settings.tracker.label}\"")
  
    issues.map do |issue|
      state = "open"
  
      if ["started", "delivered", "finished", "accepted", "rejected"].include?(issue.current_state)
        state = "progress"
      end
      if issue.current_state == "accepted"
        state = "done"
      end 
  
      {
        :title => issue.name,
        :description => issue.description,
        :status => state,
        :link => issue.url,
        :source => "tracker",
        :assignee => issue.owners && issue.owners.length > 0 ? issue.owners[0].name : "",
      }
    end
  end
end
