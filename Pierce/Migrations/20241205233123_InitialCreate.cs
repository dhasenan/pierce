using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Pierce.Migrations
{
    /// <inheritdoc />
    public partial class InitialCreate : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "feeds",
                columns: table => new
                {
                    id = table.Column<long>(type: "INTEGER", nullable: false)
                        .Annotation("Sqlite:Autoincrement", true),
                    uri = table.Column<string>(type: "TEXT", nullable: false),
                    title = table.Column<string>(type: "TEXT", nullable: false),
                    link = table.Column<string>(type: "TEXT", nullable: true),
                    description = table.Column<string>(type: "TEXT", nullable: true),
                    categories = table.Column<string>(type: "TEXT", nullable: false),
                    logo_uri = table.Column<string>(type: "TEXT", nullable: true),
                    icon_uri = table.Column<string>(type: "TEXT", nullable: true),
                    image_link_target = table.Column<string>(type: "TEXT", nullable: true),
                    image_title = table.Column<string>(type: "TEXT", nullable: true),
                    last_read = table.Column<DateTime>(type: "TEXT", nullable: false),
                    read_interval = table.Column<TimeSpan>(type: "TEXT", nullable: false),
                    next_read = table.Column<DateTime>(type: "TEXT", nullable: false),
                    errors = table.Column<int>(type: "INTEGER", nullable: false),
                    article_count = table.Column<int>(type: "INTEGER", nullable: false),
                    author_info = table.Column<string>(type: "TEXT", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_feeds", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "users",
                columns: table => new
                {
                    id = table.Column<long>(type: "INTEGER", nullable: false)
                        .Annotation("Sqlite:Autoincrement", true),
                    email = table.Column<string>(type: "TEXT", nullable: false),
                    password_hash = table.Column<string>(type: "TEXT", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_users", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "articles",
                columns: table => new
                {
                    id = table.Column<long>(type: "INTEGER", nullable: false)
                        .Annotation("Sqlite:Autoincrement", true),
                    feed_id = table.Column<long>(type: "INTEGER", nullable: false),
                    publish_date = table.Column<DateTime>(type: "TEXT", nullable: false),
                    link = table.Column<string>(type: "TEXT", nullable: true),
                    comment_link = table.Column<string>(type: "TEXT", nullable: true),
                    title = table.Column<string>(type: "TEXT", nullable: false),
                    description = table.Column<string>(type: "TEXT", nullable: false),
                    categories = table.Column<string>(type: "TEXT", nullable: false),
                    unique_id = table.Column<string>(type: "TEXT", nullable: true),
                    summary = table.Column<string>(type: "TEXT", nullable: true),
                    author_info = table.Column<string>(type: "TEXT", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_articles", x => x.id);
                    table.ForeignKey(
                        name: "fk_articles_feeds_feed_id",
                        column: x => x.feed_id,
                        principalTable: "feeds",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "subscriptions",
                columns: table => new
                {
                    id = table.Column<long>(type: "INTEGER", nullable: false)
                        .Annotation("Sqlite:Autoincrement", true),
                    feed_id = table.Column<long>(type: "INTEGER", nullable: false),
                    user_id = table.Column<long>(type: "INTEGER", nullable: false),
                    interval = table.Column<TimeSpan>(type: "TEXT", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_subscriptions", x => x.id);
                    table.ForeignKey(
                        name: "fk_subscriptions_feeds_feed_id",
                        column: x => x.feed_id,
                        principalTable: "feeds",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_subscriptions_users_user_id",
                        column: x => x.user_id,
                        principalTable: "users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "ix_articles_feed_id_publish_date",
                table: "articles",
                columns: new[] { "feed_id", "publish_date" });

            migrationBuilder.CreateIndex(
                name: "ix_feeds_uri",
                table: "feeds",
                column: "uri",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_subscriptions_feed_id",
                table: "subscriptions",
                column: "feed_id");

            migrationBuilder.CreateIndex(
                name: "ix_subscriptions_user_id_feed_id",
                table: "subscriptions",
                columns: new[] { "user_id", "feed_id" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_users_email",
                table: "users",
                column: "email",
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "articles");

            migrationBuilder.DropTable(
                name: "subscriptions");

            migrationBuilder.DropTable(
                name: "feeds");

            migrationBuilder.DropTable(
                name: "users");
        }
    }
}
