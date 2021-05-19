module Api
  module Auth
    class RegistrationsController < DeviseTokenAuth::RegistrationsController
      def create
        build_resource
        unless @resource.present?
          raise DeviseTokenAuth::Errors::NoResourceDefinedError,
                "#{self.class.name} #build_resource does not define @resource,"\
                ' execution stopped.'
        end
  
        # give redirect value from params priority
        @redirect_url = params.fetch(
          :confirm_success_url,
          DeviseTokenAuth.default_confirm_success_url
        )
  
        # success redirect url is required
        if confirmable_enabled? && !@redirect_url
          return render_create_error_missing_confirm_success_url
        end
  
        # if whitelist is set, validate redirect_url against whitelist
        return render_create_error_redirect_url_not_allowed if blacklisted_redirect_url?(@redirect_url)
  
        # 独自メソッドを追加。同じnameとcompanyを持つユーザーがいたら処理を終わらせる。
        company_and_name_duplicate_check
        # example@example.com
        # override email confirmation, must be sent manually from ctrl
        callback_name = defined?(ActiveRecord) && resource_class < ActiveRecord::Base ? :commit : :create
        resource_class.set_callback(callback_name, :after, :send_on_create_confirmation_instructions)
        resource_class.skip_callback(callback_name, :after, :send_on_create_confirmation_instructions)
  
        if @resource.respond_to? :skip_confirmation_notification!
          # Fix duplicate e-mails by disabling Devise confirmation e-mail
          @resource.skip_confirmation_notification!
        else
          # 保存されていたらjsonで返している。
          if @resource.save
            yield @resource if block_given?
    
            unless @resource.confirmed?
              # user will require email authentication
              @resource.send_confirmation_instructions({
                client_config: params[:config_name],
                redirect_url: @redirect_url
              })
            end
    
            if active_for_authentication?
              # email auth has been bypassed, authenticate user
              @token = @resource.create_token
              @resource.save!
              update_auth_header
            end
            # 保存されていたらjsonで返している。
            render_create_success
          else
            clean_up_passwords @resource
            render_create_error
          end
        end
      end

      private
      # :company( 企業名 )を追加できるようにpravateメソッドに修正を加える
      def sign_up_params
        params.permit(:name, :email, :company, :password, :password_confirmation)
      end
 
      def same_company_name_error
        render json: {
          status: 422,
          data:   resource_data,
          message: 'duplicate company error'
        }, status: 422
      end

      def company_and_name_duplicate_check
        user = User.find_by(company: @resource.company)
        if user.present? && user.name === @resource.name
          same_company_and_name_error
          return
        end
      end

      def account_update_params
        params.permit(:name, :email, :company)
      end
    end
  end
end