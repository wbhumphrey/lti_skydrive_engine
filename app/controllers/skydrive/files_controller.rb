require 'open-uri'

module Skydrive
  class FilesController < ApplicationController
    before_filter :ensure_authenticated_user, except: :download
    before_filter :ensure_valid_skydrive_token, except: :download

    def ensure_valid_skydrive_token
      head :unauthorized unless current_user.valid_skydrive_token?

      if current_user.token && current_user.token.not_before > Time.now
        current_user.token.refresh!(skydrive_client)
      end
    end

    def index
      uri = params[:uri]
      uri = nil if uri == 'root' || uri == 'undefined'
      has_parent = true
      unless uri.present?
        personal_url = current_user.token.personal_url
        data = skydrive_client.api_call(personal_url + "_api/web/lists/Documents/")
        uri = data['RootFolder']['__deferred']['uri']
        has_parent = false
      end
      folder = skydrive_client.get_folder_and_files(uri)
      folder.parent_uri = nil unless has_parent

      tp = IMS::LTI::ToolProvider.new(nil, nil, current_api_key.params)
      tp.extend IMS::LTI::Extensions::Content::ToolProvider

      # Update the files with the correct homework submission url
      folder.files.each do |file|
        file.update_content_type_data( current_api_key.accepted_extensions )
        file_download_url = download_url(token: current_api_key.access_token, file: file.server_relative_url)
        file.homework_submission_url =  tp.file_content_return_url(file_download_url, file.name)
      end

      render json: folder
    end

    def download
      api_key = ApiKey.where(access_token: params[:token]).first
      if api_key
        user = api_key.user
        uri = "#{user.token.personal_url}_api/Web/GetFileByServerRelativeUrl('#{params[:file].gsub(/ /, '%20')}')/$value"
        send_data open(uri, { "Authorization" => "Bearer #{user.token.access_token}"}, &:read)
      else
        render status: 401
      end
    end
  end
end

