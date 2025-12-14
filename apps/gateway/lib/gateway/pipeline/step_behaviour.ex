defmodule Gateway.Pipeline.StepBehaviour do
  @moduledoc """
  Behaviour for pipeline steps.
  Each step must implement these callbacks to participate in the pipeline.
  """

  @doc """
  Returns the unique name of this step.
  Must match a value in ImageStore.Pipeline.Step.valid_step_names/0.
  """
  @callback name() :: String.t()

  @doc """
  Returns the step order (1, 2, 3, etc.)
  """
  @callback order() :: pos_integer()

  @doc """
  Returns the timeout in milliseconds for this step.
  """
  @callback timeout() :: pos_integer()

  @doc """
  Executes the step with the given image data and metadata.

  ## Parameters
    - image_id: UUID of the image being processed
    - image_bytes: Raw binary image data
    - metadata: Map containing results from previous steps and image metadata

  ## Returns
    - {:ok, output_data} on success where output_data is a map
    - {:error, reason} on failure
  """
  @callback execute(image_id :: binary(), image_bytes :: binary(), metadata :: map()) ::
              {:ok, map()} | {:error, term()}
end
