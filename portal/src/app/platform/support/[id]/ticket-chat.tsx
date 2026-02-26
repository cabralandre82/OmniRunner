"use client";

import { useRouter } from "next/navigation";
import { useEffect, useRef, useState } from "react";

interface Message {
  id: string;
  sender_id: string;
  sender_role: string;
  body: string;
  created_at: string;
}

interface Props {
  ticketId: string;
  status: string;
  initialMessages: Message[];
  userId: string;
}

export function TicketChat({
  ticketId,
  status: initialStatus,
  initialMessages,
  userId,
}: Props) {
  const router = useRouter();
  const [messages, setMessages] = useState<Message[]>(initialMessages);
  const [status, setStatus] = useState(initialStatus);
  const [body, setBody] = useState("");
  const [sending, setSending] = useState(false);
  const [closing, setClosing] = useState(false);
  const [reopening, setReopening] = useState(false);
  const bottomRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages]);

  async function handleSend() {
    const text = body.trim();
    if (!text) return;

    setSending(true);
    try {
      const res = await fetch(`/api/platform/support`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          action: "reply",
          ticket_id: ticketId,
          message: text,
        }),
      });

      if (!res.ok) {
        const d = await res.json();
        alert(`Erro: ${d.error ?? "Falha"}`);
        return;
      }

      setBody("");
      setStatus("answered");
      router.refresh();

      setMessages((prev) => [
        ...prev,
        {
          id: crypto.randomUUID(),
          sender_id: userId,
          sender_role: "platform",
          body: text,
          created_at: new Date().toISOString(),
        },
      ]);
    } finally {
      setSending(false);
    }
  }

  async function handleClose() {
    if (!window.confirm("Fechar este chamado?")) return;

    setClosing(true);
    try {
      const res = await fetch(`/api/platform/support`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "close", ticket_id: ticketId }),
      });

      if (!res.ok) {
        const d = await res.json();
        alert(`Erro: ${d.error ?? "Falha"}`);
        return;
      }

      setStatus("closed");
      router.refresh();
    } finally {
      setClosing(false);
    }
  }

  async function handleReopen() {
    setReopening(true);
    try {
      const res = await fetch(`/api/platform/support`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "reopen", ticket_id: ticketId }),
      });

      if (!res.ok) {
        const d = await res.json();
        alert(`Erro: ${d.error ?? "Falha"}`);
        return;
      }

      setStatus("open");
      router.refresh();
    } finally {
      setReopening(false);
    }
  }

  const isClosed = status === "closed";

  return (
    <div className="rounded-xl border border-gray-200 bg-white shadow-sm">
      {/* Messages */}
      <div className="max-h-[60vh] overflow-y-auto p-4 space-y-3">
        {messages.length === 0 ? (
          <p className="py-8 text-center text-sm text-gray-400">
            Nenhuma mensagem.
          </p>
        ) : (
          messages.map((m) => {
            const isPlatform = m.sender_role === "platform";
            const time = new Date(m.created_at).toLocaleString("pt-BR", {
              day: "2-digit",
              month: "2-digit",
              hour: "2-digit",
              minute: "2-digit",
            });

            return (
              <div
                key={m.id}
                className={`flex ${isPlatform ? "justify-end" : "justify-start"}`}
              >
                <div
                  className={`max-w-[75%] rounded-2xl px-4 py-2.5 ${
                    isPlatform
                      ? "rounded-br-md bg-blue-600 text-white"
                      : "rounded-bl-md bg-gray-100 text-gray-900"
                  }`}
                >
                  <p className="text-xs font-semibold mb-0.5 opacity-70">
                    {isPlatform ? "Equipe Omni Runner" : "Assessoria"}
                  </p>
                  <p className="text-sm whitespace-pre-wrap leading-relaxed">
                    {m.body}
                  </p>
                  <p
                    className={`mt-1 text-[10px] ${
                      isPlatform ? "text-blue-200" : "text-gray-400"
                    }`}
                  >
                    {time}
                  </p>
                </div>
              </div>
            );
          })
        )}
        <div ref={bottomRef} />
      </div>

      {/* Input / Actions */}
      <div className="border-t border-gray-200 p-4">
        {isClosed ? (
          <div className="flex items-center justify-between">
            <p className="text-sm text-gray-500">Chamado encerrado.</p>
            <button
              onClick={handleReopen}
              disabled={reopening}
              className="rounded-lg bg-gray-100 px-3 py-1.5 text-xs font-medium text-gray-600 hover:bg-gray-200 disabled:opacity-50"
            >
              {reopening ? "..." : "Reabrir"}
            </button>
          </div>
        ) : (
          <div className="space-y-3">
            <div className="flex gap-2">
              <textarea
                value={body}
                onChange={(e) => setBody(e.target.value)}
                placeholder="Responder como plataforma..."
                rows={2}
                className="flex-1 resize-none rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500"
                onKeyDown={(e) => {
                  if (e.key === "Enter" && !e.shiftKey) {
                    e.preventDefault();
                    handleSend();
                  }
                }}
              />
            </div>
            <div className="flex justify-between">
              <button
                onClick={handleClose}
                disabled={closing}
                className="rounded-lg bg-gray-100 px-3 py-1.5 text-xs font-medium text-gray-600 hover:bg-gray-200 disabled:opacity-50"
              >
                {closing ? "..." : "Fechar chamado"}
              </button>
              <button
                onClick={handleSend}
                disabled={sending || !body.trim()}
                className="rounded-lg bg-blue-600 px-4 py-1.5 text-sm font-medium text-white hover:bg-blue-700 disabled:opacity-50"
              >
                {sending ? "Enviando..." : "Enviar"}
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
