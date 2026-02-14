export function Skeleton({ className = "" }: { className?: string }) {
  return <div className={`skeleton h-6 w-24 ${className}`} />;
}

export function CardSkeleton() {
  return (
    <div className="rounded-xl border border-dark-600 bg-dark-800 p-5">
      <Skeleton className="h-4 w-20 mb-3" />
      <Skeleton className="h-8 w-32" />
    </div>
  );
}
