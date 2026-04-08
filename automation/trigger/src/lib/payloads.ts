export type StoryImportJobPayload = {
  jobId: string;
  sourceStoragePath: string;
  requestedByUserId: string | null;
  environment: string;
};

export type StoryImportReviewPayload = StoryImportJobPayload & {
  reviewUrl?: string;
};

export type StoryImportApprovalOutput = {
  status: "approved" | "rejected";
  reviewer?: string;
  note?: string;
};

export type StoryImportPromotePayload = {
  jobId: string;
  environment: string;
  approvedBy?: string;
};
