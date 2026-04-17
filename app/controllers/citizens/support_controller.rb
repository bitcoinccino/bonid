module Citizens
  class SupportController < Citizens::BaseController
    def index
      @faq_categories = [
        {
          key: "getting_started",
          icon: "ri-rocket-line",
          label: t("citizens.support.categories.getting_started"),
          questions: %w[q1 q4 q5 q6]
        },
        {
          key: "understanding",
          icon: "ri-book-open-line",
          label: t("citizens.support.categories.understanding"),
          questions: %w[q2 q3 q7]
        },
        {
          key: "security",
          icon: "ri-shield-check-line",
          label: t("citizens.support.categories.security"),
          questions: %w[q10 q11 q12]
        },
        {
          key: "account",
          icon: "ri-user-settings-line",
          label: t("citizens.support.categories.account"),
          questions: %w[q8 q9]
        },
        {
          key: "election",
          icon: "ri-government-line",
          label: t("citizens.support.categories.election"),
          questions: %w[q13 q14 q15 q16 q17 q18 q19]
        }
      ]

      @faq_items = t("main.faq.items")

      # Top 3 trending questions (most commonly accessed)
      @trending_keys = %w[q5 q7 q12]
    end
  end
end
