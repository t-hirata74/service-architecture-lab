-- AlterTable
ALTER TABLE `sync_ops` MODIFY `entity_type` ENUM('team', 'workflow_state', 'issue', 'label', 'issue_label', 'comment', 'workspace_member') NOT NULL;
