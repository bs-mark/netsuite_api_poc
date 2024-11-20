class OrdersController < ApplicationController
  def index
    @result = flash[:result]
    @error_message = flash[:error_message]
    @logs = Log.order(created_at: :desc).limit(5)
  end

  def fetch_order

    order_id = params[:order_id]
    auth_type = params[:auth_type].to_sym

    service = NetsuiteService.new(auth_type: auth_type)
    @result = service.get_sales_order(order_id)


  rescue StandardError => e
    flash[:error_message] = e.message
  ensure
    redirect_to url_for(controller: 'orders', action: 'index') # Redirect to index action
  end
end

