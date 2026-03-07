"use client";

import { useState, useMemo } from "react";

export interface HelpArticle {
  id: string;
  title: string;
  content: string;
}

export interface HelpCategory {
  id: string;
  label: string;
  articles: HelpArticle[];
}

interface HelpCenterContentProps {
  categories: HelpCategory[];
}

function normalizeForSearch(text: string): string {
  return text
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "");
}

function matchesSearch(text: string, query: string): boolean {
  if (!query.trim()) return true;
  const nText = normalizeForSearch(text);
  const nQuery = normalizeForSearch(query.trim());
  return nText.includes(nQuery);
}

export function HelpCenterContent({ categories }: HelpCenterContentProps) {
  const [search, setSearch] = useState("");
  const [expandedCategories, setExpandedCategories] = useState<Record<string, boolean>>(() => {
    const init: Record<string, boolean> = {};
    categories.forEach((c) => {
      init[c.id] = true;
    });
    return init;
  });
  const [expandedArticles, setExpandedArticles] = useState<Record<string, boolean>>({});

  const filteredCategories = useMemo(() => {
    if (!search.trim()) return categories;
    return categories
      .map((cat) => ({
        ...cat,
        articles: cat.articles.filter(
          (a) =>
            matchesSearch(a.title, search) || matchesSearch(a.content, search)
        ),
      }))
      .filter((cat) => cat.articles.length > 0);
  }, [categories, search]);

  const toggleCategory = (id: string) => {
    setExpandedCategories((prev) => ({ ...prev, [id]: !prev[id] }));
  };

  const toggleArticle = (id: string) => {
    setExpandedArticles((prev) => ({ ...prev, [id]: !prev[id] }));
  };

  return (
    <div className="space-y-8">
      {/* Search */}
      <div className="relative">
        <svg
          className="absolute left-4 top-1/2 h-4 w-4 -translate-y-1/2 text-content-muted"
          fill="none"
          viewBox="0 0 24 24"
          strokeWidth={1.5}
          stroke="currentColor"
        >
          <path
            strokeLinecap="round"
            strokeLinejoin="round"
            d="M21 21l-5.197-5.197m0 0A7.5 7.5 0 105.196 5.196a7.5 7.5 0 0010.607 10.607z"
          />
        </svg>
        <input
          type="search"
          placeholder="Buscar artigos..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          className="w-full rounded-xl border border-border bg-surface py-3 pl-11 pr-4 text-body text-content-primary placeholder:text-content-muted focus:border-brand focus:outline-none focus:ring-2 focus:ring-brand/20"
          aria-label="Buscar artigos da central de ajuda"
        />
      </div>

      {/* Categories */}
      <div className="space-y-4">
        {filteredCategories.length === 0 ? (
          <div className="rounded-xl border border-border bg-surface p-8 text-center">
            <p className="text-content-secondary">
              Nenhum artigo encontrado para &quot;{search}&quot;. Tente outros termos.
            </p>
          </div>
        ) : (
          filteredCategories.map((category) => {
            const isExpanded = expandedCategories[category.id] ?? true;
            return (
              <section
                key={category.id}
                className="rounded-xl border border-border bg-surface shadow-sm overflow-hidden"
              >
                <button
                  onClick={() => toggleCategory(category.id)}
                  className="flex w-full items-center justify-between px-5 py-4 text-left hover:bg-surface-elevated transition-colors"
                >
                  <h2 className="text-title-md text-content-primary font-semibold">
                    {category.label}
                  </h2>
                  <svg
                    className={`h-5 w-5 text-content-muted transition-transform duration-fast ${
                      isExpanded ? "rotate-180" : ""
                    }`}
                    fill="none"
                    viewBox="0 0 24 24"
                    strokeWidth={2}
                    stroke="currentColor"
                  >
                    <path
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      d="M19.5 8.25l-7.5 7.5-7.5-7.5"
                    />
                  </svg>
                </button>
                {isExpanded && (
                  <div className="border-t border-border-subtle px-5 pb-5 pt-2 space-y-3">
                    {category.articles.map((article) => {
                      const isArticleOpen = expandedArticles[article.id] ?? false;
                      return (
                        <div
                          key={article.id}
                          className="rounded-lg border border-border-subtle bg-bg-primary overflow-hidden"
                        >
                          <button
                            onClick={() => toggleArticle(article.id)}
                            className="flex w-full items-center justify-between px-4 py-3 text-left hover:bg-surface-elevated transition-colors"
                          >
                            <span className="text-label font-medium text-content-primary">
                              {article.title}
                            </span>
                            <svg
                              className={`h-4 w-4 text-content-muted flex-shrink-0 ml-2 transition-transform duration-fast ${
                                isArticleOpen ? "rotate-180" : ""
                              }`}
                              fill="none"
                              viewBox="0 0 24 24"
                              strokeWidth={2}
                              stroke="currentColor"
                            >
                              <path
                                strokeLinecap="round"
                                strokeLinejoin="round"
                                d="M19.5 8.25l-7.5 7.5-7.5-7.5"
                              />
                            </svg>
                          </button>
                          {isArticleOpen && (
                            <div className="border-t border-border-subtle px-4 py-4">
                              <div className="prose prose-sm max-w-none text-content-secondary text-body leading-relaxed whitespace-pre-line">
                                {article.content}
                              </div>
                            </div>
                          )}
                        </div>
                      );
                    })}
                  </div>
                )}
              </section>
            );
          })
        )}
      </div>
    </div>
  );
}
