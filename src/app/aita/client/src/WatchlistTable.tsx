import { useState } from 'react';
import {
  Badge,
  Button,
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
  Skeleton,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@databricks/appkit-ui/react';
import { ChevronLeft, ChevronRight, ClipboardCheck, MessageSquareText, Users } from 'lucide-react';
import type { WatchlistItem, WatchlistResponse, WatchlistReviewStatus } from '../../shared/app-state';
import { WatchlistReviewCell, WatchlistReviewDialog } from './WatchlistReview';

export const ALL_FILTERS = 'all';

interface WatchlistTableProps {
  businessLine: string;
  data: WatchlistResponse | null;
  error: string | null;
  flag: string;
  loading: boolean;
  page: number;
  reviewStatus: string;
  onAskAita: (employeeId: string) => void;
  onBusinessLineChange: (value: string) => void;
  onFlagChange: (value: string) => void;
  onPageChange: (value: number) => void;
  onReset: () => void;
  onReview: (employeeId: string, status: WatchlistReviewStatus, note: string) => Promise<boolean>;
  onReviewStatusChange: (value: string) => void;
}

export function WatchlistTable({
  businessLine,
  data,
  error,
  flag,
  loading,
  page,
  reviewStatus,
  onAskAita,
  onBusinessLineChange,
  onFlagChange,
  onPageChange,
  onReset,
  onReview,
  onReviewStatusChange,
}: WatchlistTableProps) {
  const [selectedItem, setSelectedItem] = useState<WatchlistItem | null>(null);

  return (
    <>
      <Card>
        <CardHeader>
          <CardTitle>Flagged employees</CardTitle>
          <div className="flex flex-wrap gap-3 pt-2">
            <Select value={businessLine} onValueChange={onBusinessLineChange}>
              <SelectTrigger className="w-64" aria-label="Business line filter">
                <SelectValue placeholder="Business line" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value={ALL_FILTERS}>All business lines</SelectItem>
                {data?.filters.businessLines.map((line) => (
                  <SelectItem key={line} value={line}>
                    {line}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            <Select value={flag} onValueChange={onFlagChange}>
              <SelectTrigger className="w-64" aria-label="Risk flag filter">
                <SelectValue placeholder="Risk flag" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value={ALL_FILTERS}>All risk flags</SelectItem>
                {data?.filters.flags.map((value) => (
                  <SelectItem key={value} value={value}>
                    {formatLabel(value)}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            <Select value={reviewStatus} onValueChange={onReviewStatusChange}>
              <SelectTrigger className="w-64" aria-label="Review status filter">
                <SelectValue placeholder="Review status" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value={ALL_FILTERS}>All review statuses</SelectItem>
                {data?.filters.reviewStatuses.map((value) => (
                  <SelectItem key={value} value={value}>
                    {formatLabel(value)}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
        </CardHeader>
        <CardContent>
          {loading && !data ? (
            <div className="space-y-3">
              {[1, 2, 3, 4, 5].map((item) => (
                <Skeleton key={item} className="h-16 w-full" />
              ))}
            </div>
          ) : data?.items.length ? (
            <>
              <div className="overflow-x-auto">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Employee</TableHead>
                      <TableHead>Business line</TableHead>
                      <TableHead>Flags</TableHead>
                      <TableHead>Reasons</TableHead>
                      <TableHead>Review</TableHead>
                      <TableHead className="text-right">Actions</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {data.items.map((item) => (
                      <TableRow key={item.employeeId}>
                        <TableCell className="font-medium">{item.employeeId}</TableCell>
                        <TableCell>{item.businessLine}</TableCell>
                        <TableCell>
                          <div className="flex max-w-xs flex-wrap gap-1">
                            {item.riskFlags.map((riskFlag) => (
                              <Badge key={riskFlag} variant="secondary">
                                {formatLabel(riskFlag)}
                              </Badge>
                            ))}
                          </div>
                        </TableCell>
                        <TableCell>
                          <ul className="min-w-80 list-disc space-y-1 pl-4 text-sm">
                            {item.reasons.map((reason) => (
                              <li key={reason}>{reason}</li>
                            ))}
                          </ul>
                        </TableCell>
                        <TableCell>
                          <WatchlistReviewCell item={item} />
                        </TableCell>
                        <TableCell className="text-right">
                          <div className="flex justify-end gap-2">
                            <Button size="sm" variant="outline" onClick={() => setSelectedItem(item)}>
                              <ClipboardCheck className="h-4 w-4" /> Review
                            </Button>
                            <Button size="sm" variant="outline" onClick={() => onAskAita(item.employeeId)}>
                              <MessageSquareText className="h-4 w-4" /> Ask Aita
                            </Button>
                          </div>
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </div>
              <div className="mt-4 flex items-center justify-between gap-3">
                <p className="text-sm text-muted-foreground">
                  {data.pagination.total.toLocaleString()} results · page {data.pagination.page} of{' '}
                  {data.pagination.totalPages}
                </p>
                <div className="flex gap-2">
                  <Button
                    variant="outline"
                    size="sm"
                    disabled={page <= 1 || loading}
                    onClick={() => onPageChange(page - 1)}
                  >
                    <ChevronLeft className="h-4 w-4" /> Previous
                  </Button>
                  <Button
                    variant="outline"
                    size="sm"
                    disabled={page >= data.pagination.totalPages || loading}
                    onClick={() => onPageChange(page + 1)}
                  >
                    Next <ChevronRight className="h-4 w-4" />
                  </Button>
                </div>
              </div>
            </>
          ) : !loading && !error ? (
            <Empty>
              <EmptyHeader>
                <EmptyMedia variant="icon">
                  <Users />
                </EmptyMedia>
                <EmptyTitle>No employees match these filters</EmptyTitle>
                <EmptyDescription>Reset the filters to view the complete synced watchlist.</EmptyDescription>
              </EmptyHeader>
              <EmptyContent>
                <Button variant="outline" onClick={onReset}>
                  Reset filters
                </Button>
              </EmptyContent>
            </Empty>
          ) : null}
        </CardContent>
      </Card>

      {selectedItem && (
        <WatchlistReviewDialog
          item={selectedItem}
          statuses={data?.filters.reviewStatuses ?? []}
          onClose={() => setSelectedItem(null)}
          onReview={onReview}
        />
      )}
    </>
  );
}

function formatLabel(value: string): string {
  return value.replaceAll('_', ' ').replace(/\b\w/g, (letter) => letter.toUpperCase());
}
