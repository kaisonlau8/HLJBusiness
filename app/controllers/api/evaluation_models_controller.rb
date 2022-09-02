class Api::EvaluationModelsController < Api::ApiController
  before_action :need_admin, except: %i[index show]
  skip_before_action :header_authorization_verify, only: [:show]

  def index
    models = EvaluationModel.all
    models = models.map do |model|
      model[:using] = !model.projects.inject(true) do |blank, project|
        blank && project.evaluation_records.blank?
      end
      model
    end
    render json: { ok: true, models: models }
  end

  def show
    model = EvaluationModel.find(params[:id])
    model[:using] = !model&.projects&.inject(true) do |blank, project|
      blank && project.evaluation_records.blank?
    end
    render json: { ok: true, model: model }
  end

  def create
    unless params_valid?
      return render json: { ok: false, error: 'params_not_valid' }, status: :bad_request
    end

    model = EvaluationModel.create!(model_params)
    render json: { ok: true, model: model }
  end

  def update
    unless params_valid?
      return render json: { ok: false, error: 'params_not_valid' }, status: :bad_request
    end

    model = EvaluationModel.find(params[:id])
    model&.update!(model_params)
    using = !model&.projects&.inject(true) do |blank, project|
      blank && project.evaluation_records.blank?
    end
    return render json: { ok: false }, status: :conflict if using

    render json: { ok: true, model: model }
  end

  def destroy
    EvaluationModel.find(params[:id])&.destroy!
    render json: { ok: true }
  end

  private

  def model_params
    result = params.require(:model).permit(
      :name,
      :evaluation_type,
      levels: %i[name max min],
      role_percentages: %i[role percentage],
      evaluations: [{ _id: {} }, :content,
                    details: [{ _id: {} }, :item, :standard, :score]]
    )
    result[:role_percentages] = parse_role_percentages result[:role_percentages]
    result
  end

  def parse_role_percentages(role_percentages)
    role_percentages.map do |role_percentage|
      {
        role: role_percentage[:role],
        percentage: BigDecimal(role_percentage[:percentage].to_s)
      }
    end
  end

  def total_score
    model_params[:evaluations].inject(0) do |sum1, evaluation|
      sum1 + evaluation[:details].inject(0) do |sum2, detail|
        sum2 + detail[:score]
      end
    end
  end

  def levels_valid?
    scores = Array.new(total_score + 2, 0)
    model_params[:levels].each do |level|
      return false if level[:min].negative? || level[:max] > total_score

      scores[level[:min]] += 1
      scores[level[:max] + 1] -= 1
    end
    sum = 0
    (0...scores.size - 1).each do |i|
      sum += scores[i]
      return false if sum != 1
    end
    true
  end

  def role_percentages_valid?
    total = model_params[:role_percentages].inject(0) do |sum, role_percentage|
      sum + role_percentage[:percentage]
    end
    total == BigDecimal(1)
  end

  def params_valid?
    levels_valid? && role_percentages_valid?
  end
end
