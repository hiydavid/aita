import { useState } from 'react';
import {
  Badge,
  Button,
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  Label,
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
  Textarea,
} from '@databricks/appkit-ui/react';
import { WATCHLIST_REVIEW_STATUSES, type WatchlistItem, type WatchlistReviewStatus } from '../../shared/app-state';

interface WatchlistReviewDialogProps {
  item: WatchlistItem;
  statuses: WatchlistReviewStatus[];
  onClose: () => void;
  onReview: (employeeId: string, status: WatchlistReviewStatus, note: string) => Promise<boolean>;
}

export function WatchlistReviewCell({ item }: { item: WatchlistItem }) {
  return (
    <div className="min-w-44 space-y-1">
      <Badge variant={reviewBadgeVariant(item.review.status)}>{formatLabel(item.review.status)}</Badge>
      {item.review.reviewer && (
        <p className="text-xs text-muted-foreground">
          {item.review.reviewer}
          {item.review.createdAt ? ` · ${new Date(item.review.createdAt).toLocaleDateString()}` : ''}
        </p>
      )}
      {item.review.note && <p className="max-w-xs text-xs">{item.review.note}</p>}
    </div>
  );
}

export function WatchlistReviewDialog({ item, statuses, onClose, onReview }: WatchlistReviewDialogProps) {
  const [status, setStatus] = useState(item.review.status);
  const [note, setNote] = useState(item.review.note ?? '');
  const [saving, setSaving] = useState(false);

  async function save() {
    setSaving(true);
    try {
      if (await onReview(item.employeeId, status, note)) onClose();
    } finally {
      setSaving(false);
    }
  }

  return (
    <Dialog open onOpenChange={(open) => !open && !saving && onClose()}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>Update review status</DialogTitle>
          <DialogDescription>
            Record the shared review state for {item.employeeId}. Each update is retained as a new event.
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-4 py-2">
          <div className="space-y-2">
            <Label htmlFor="review-status">Status</Label>
            <Select value={status} onValueChange={(value) => isReviewStatus(value) && setStatus(value)}>
              <SelectTrigger id="review-status" aria-label="Updated review status">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {statuses.map((value) => (
                  <SelectItem key={value} value={value}>
                    {formatLabel(value)}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-2">
            <Label htmlFor="review-note">Note</Label>
            <Textarea
              id="review-note"
              maxLength={500}
              rows={4}
              value={note}
              onChange={(event) => setNote(event.target.value)}
              placeholder="Optional context for authorized reviewers"
            />
            <p className="text-right text-xs text-muted-foreground">{note.length}/500</p>
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" disabled={saving} onClick={onClose}>
            Cancel
          </Button>
          <Button disabled={saving} onClick={() => void save()}>
            {saving ? 'Saving…' : 'Save review'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function formatLabel(value: string): string {
  return value.replaceAll('_', ' ').replace(/\b\w/g, (letter) => letter.toUpperCase());
}

function reviewBadgeVariant(status: WatchlistReviewStatus): 'default' | 'secondary' | 'outline' {
  if (status === 'reviewed') return 'default';
  if (status === 'in_review') return 'secondary';
  return 'outline';
}

function isReviewStatus(value: string): value is WatchlistReviewStatus {
  return WATCHLIST_REVIEW_STATUSES.some((status) => status === value);
}
