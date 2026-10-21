defmodule Foreman.Requests.Request do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @derive {Jason.Encoder,
           only: [
             :id,
             :repo_key,
             :bead_id,
             :kind,
             :actor,
             :session,
             :facts,
             :state,
             :outcome,
             :note,
             :inserted_at,
             :updated_at
           ]}
  schema "approval_requests" do
    field :repo_key, :string
    field :bead_id, :string
    field :kind, :string
    field :actor, :string
    field :session, :string
    field :facts, :map
    field :state, :string
    field :outcome, :map, default: %{}
    field :note, :string
    field :priority, :integer, virtual: true
    field :file, :integer, virtual: true
    field :changed_on_board, :boolean, virtual: true, default: false
    field :jump_order, :integer, virtual: true
    field :priority_order, :integer, virtual: true
    field :key, :any, virtual: true
    timestamps(type: :utc_datetime_usec)
  end
end
