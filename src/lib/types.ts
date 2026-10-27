export interface ReviewItem {
  id: string;
  title: string;
  projectId: string;
  projectTitle: string;
  isUpdate: boolean;
  evidenceVersion: number;
  userId: string;
  username: string;
  profilePictureUrl: string;
  status: string;
  queuedAt: string;
  submittedAt: string;
  weekNumber: number;
  seconds: number;
  platforms: string[];
  hold: string | null;
  holdNote: string | null;
  holdAt: string | null;
  evidenceStatus: string;
  evidenceBuiltAt: string;
  danger: number;
  warn: number;
  claimedBy: string | null;
  claimedByMe: boolean;
  decision: string | null;
  decidedBy: string | null;
  decidedAt: string | null;
  triageTier: string | null;
  triagedBy: string | null;
  triagedAt: string | null;
  stage: string;
  chainId: string;
  chainTitle: string;
}

export interface ReviewResponse {
  queue: string;
  filter: string;
  items: ReviewItem[];
}
