# Rails 規約上の primary abstract record。
# 本リポでは各 Engine が `Core::ApplicationRecord` / `Catalog::ApplicationRecord` 等の
# Engine-local な abstract base を持ち、model はそれを継承する (top-level ApplicationRecord は
# 直接継承しない)。
# 削除可能ではあるが、Rails 8 内部の primary connection 解決に使われるため `primary_abstract_class`
# 宣言として残す。
class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
end
