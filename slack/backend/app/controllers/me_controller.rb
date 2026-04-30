class MeController < ApplicationController
  def show
    render json: {
      id: current_user.id,
      display_name: current_user.display_name,
      email: current_user.account.email
    }
  end
end
