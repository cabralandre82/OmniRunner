import { signOut, clearPortalGroup } from "@/lib/actions";

interface HeaderProps {
  groupName: string;
  userEmail: string;
  multiGroup: boolean;
}

export function Header({ groupName, userEmail, multiGroup }: HeaderProps) {
  return (
    <header className="flex h-14 items-center justify-between border-b border-gray-200 bg-white px-6">
      <div className="flex items-center gap-3">
        <h3 className="text-sm font-semibold text-gray-900">{groupName}</h3>
        {multiGroup && (
          <form action={clearPortalGroup}>
            <button
              type="submit"
              className="rounded bg-gray-100 px-2 py-0.5 text-xs text-gray-500 hover:bg-gray-200"
            >
              trocar
            </button>
          </form>
        )}
      </div>

      <div className="flex items-center gap-4">
        <span className="text-xs text-gray-500">{userEmail}</span>
        <form action={signOut}>
          <button
            type="submit"
            className="rounded-lg px-3 py-1.5 text-xs font-medium text-gray-600 hover:bg-gray-100"
          >
            Sair
          </button>
        </form>
      </div>
    </header>
  );
}
