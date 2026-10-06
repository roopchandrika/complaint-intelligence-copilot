{#- Generic test: every value of the column is between min_value and max_value (inclusive).
    Returns the failing rows. Either bound may be omitted. -#}
{% test accepted_range(model, column_name, min_value=none, max_value=none) %}
select {{ column_name }} as failing_value
from {{ model }}
where {{ column_name }} is not null
  and (
    {% if min_value is not none %} {{ column_name }} < {{ min_value }} {% else %} false {% endif %}
    or
    {% if max_value is not none %} {{ column_name }} > {{ max_value }} {% else %} false {% endif %}
  )
{% endtest %}
