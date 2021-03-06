require 'ims/lti'

module Skydrive
  class LaunchController < ApplicationController
    include ActionController::Cookies

    before_filter :ensure_authenticated_user, only: :skydrive_authorized

    def tool_provider
      require 'oauth/request_proxy/rack_request'

      @account = Account.where(key: params['oauth_consumer_key']).first

      if @account
        key = @account.key
        secret = @account.secret
      end

      tp = IMS::LTI::ToolProvider.new(key, secret, params)

      if !key
        tp.lti_errorlog = "Invalid consumer key or secret"
      elsif !secret
        tp.lti_errorlog = "Consumer key wasn't recognized"
      elsif !tp.valid_request?(request)
        tp.lti_errorlog = "The OAuth signature was invalid"
      elsif Time.now.utc.to_i - tp.request_oauth_timestamp.to_i > 120
        tp.lti_errorlog = "Your request is too old"
      end

      #
      ## this isn't actually checking anything like it should, just want people
      ## implementing real tools to be aware they need to check the nonce
      #if was_nonce_used_in_last_x_minutes?(@tp.request_oauth_nonce, 60)
      #  register_error "Why are you reusing the nonce?"
      #  return false
      #end
      #
      ## save the launch parameters for use in later request
      ##session['launch_params'] = @tp.to_params
      #
      #@username = @tp.username("Dude")

      return tp
    end

    def basic_launch
      tp = tool_provider
      if tp.lti_errorlog
        render text: tp.lti_errorlog, status: 400, layout: "skydrive/error"
        return
      end

      unless client_domain = tp.get_custom_param('sharepoint_client_domain')
        render text: "Missing sharepoint client domain", status: 400, layout: "skydrive/error"
        return
      end

      user = @account.users.where(lti_user_id: tp.user_id).first ||
          @account.users.create(
              lti_user_id: tp.user_id,
              name: tp.lis_person_name_full,
              username: tp.user_id,
              email: tp.lis_person_contact_email_primary,
          )

      if user.token
        user.token.update_attributes(client_domain: "#{client_domain}-my.sharepoint.com")
      else
        user.token = Token.create(client_domain: "#{client_domain}-my.sharepoint.com")
      end
      user.cleanup_api_keys
      
      code = user.session_api_key(params).oauth_code
      redirect_to "#{root_path}#/launch/#{code}"
    end

    def skydrive_authorized
      skydrive_token = current_user.token
      if skydrive_token && skydrive_token.requires_refresh?
        skydrive_token.refresh!(skydrive_client)
      end

      if skydrive_token && skydrive_token.is_valid?
        render json: {}, status: 201
      else
        code = current_user.api_keys.active.skydrive_oauth.create.oauth_code
        if current_user.account.admin
          #Get the user's access token
          auth_url = skydrive_client.app_redirect_uri(microsoft_oauth_url, state: code)
        else
          #Authorize the tenant
          auth_url = skydrive_client.oauth_authorize_redirect_uri(microsoft_oauth_url, state: code)
        end
        render text: auth_url, status: 401
      end
    end

    def app_redirect
      @current_user = ApiKey.trade_oauth_code_for_access_token(params['state']).user

      token = @current_user.token

      token.token_type = Token::USER
      token.refresh_token = params[:SPAppToken]
      token.refresh!(skydrive_client)

      redirect_to "#{root_path}#/oauth/callback"
    end

    def microsoft_oauth
      @current_user = ApiKey.trade_oauth_code_for_access_token(params['state']).user

      results = skydrive_client.authorize_app(microsoft_oauth_url, params['code'])

      unless results.key? 'error'
        results.merge!(token_type: Token::ADMIN, personal_url: skydrive_client.get_user['PersonalUrl'])
        @current_user.token.update_attributes(results)
        @current_user.account.update_attributes(admin: @current_user)
      end

      redirect_to "#{root_path}#/oauth/callback"
    end

    def xml_config
      # ie http://localhost:9393/config?sharepoint_client_domain=my_subdomain
      host = request.scheme + "://" + request.host_with_port + "/"

      if params['sharepoint_client_domain']
        url = "#{request.protocol}#{request.host_with_port}#{launch_path}"
        title = "Onedrive Pro"
        tc = IMS::LTI::ToolConfig.new(:title => title, :launch_url => url)
        tc.extend IMS::LTI::Extensions::Canvas::ToolConfig
        tc.description = 'Allows you to pull in documents from Onedrive Pro to canvas'
        tc.canvas_privacy_public!
        tc.canvas_domain!(request.host)
        tc.canvas_icon_url!("#{host}assets/skydrive/skydrive_icon.png")
        tc.canvas_selector_dimensions!(700,600)
        tc.canvas_text!(title)
        tc.canvas_homework_submission!
        tc.canvas_account_navigation!
        tc.canvas_course_navigation!(visibility: 'admin')
        tc.set_ext_param(
            IMS::LTI::Extensions::Canvas::ToolConfig::PLATFORM, :custom_fields,
            {sharepoint_client_domain: params['sharepoint_client_domain']})
        render xml: tc.to_xml
      else
        render text: 'The sharepoint_client_domain is a required parameter.'
      end
    end
  end
end
