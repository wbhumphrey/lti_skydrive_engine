Skydrive::Engine.routes.draw do
  root "ember#index"

  get 'health_check' => 'ember#health_check'
  get '/download/file' => 'files#download', as: :download

  scope "api/v1" do
    resources :users, except: [:new, :edit]
    get 'files(/*uri)' => 'files#index'
    get 'skydrive_authorized' => 'launch#skydrive_authorized'
  end

  post 'session' => 'session#create'

  #LTI launch paths
  get 'launch' => 'launch#basic_launch', :as => :launch
  post 'launch' => 'launch#basic_launch'
  get 'backdoor' => 'launch#backdoor_launch'
  get 'microsoft_oauth' => 'launch#microsoft_oauth'
  post 'microsoft_oauth' => 'launch#app_redirect'

  get 'config' => 'launch#xml_config'

  post 'oauth2/token' => 'api_keys#oauth2_token'
end
