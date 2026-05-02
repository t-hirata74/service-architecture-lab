# ADR 0004 / Phase 3 レビュー §6.2:
# 同じ marker (e.g. "src_3") が同じ answer に複数回 insert されないよう DB で UNIQUE.
# RagOrchestrator は find_or_create_by で取り回し、重複 citation event を吸収する.
class AddUniqueIndexToCitationsMarker < ActiveRecord::Migration[8.1]
  def change
    add_index :citations, %i[answer_id marker], unique: true,
              name: "idx_citations_answer_marker_unique"
  end
end
