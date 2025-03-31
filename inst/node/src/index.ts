import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { spawn } from 'child_process';
import { z } from "zod";

const server = new Server({
  name: "r-mcp",
  version: "1.0.0"
}, {
  capabilities: {
    tools: {}
  }
});

async function executeR(rScript: string): Promise<string> {
  const rscriptPath = process.env.R_HOME ? 
    `${process.env.R_HOME}/bin/Rscript` : 
    process.env.RSCRIPT_PATH || 'Rscript';
    
  return new Promise((resolve, reject) => {
    const child = spawn(rscriptPath, ['-e', rScript]);
    
    let stdout = '';
    let stderr = '';
    
    child.stdout.on('data', (data) => {
      stdout += data.toString();
    });
    
    child.stderr.on('data', (data) => {
      stderr += data.toString();
    });
    
    child.on('close', (code) => {
      if (code !== 0) {
        reject(new Error(`R script failed with code ${code}: ${stderr}`));
      } else {
        resolve(stdout);
      }
    });
  });
}

// Register tools that map to btw functions
const toolsListSchema = z.object({
  method: z.literal("tools/list"),
  params: z.object({}).optional()
});

server.setRequestHandler(toolsListSchema, async () => {
  return {
    tools: [
      {
        name: "get_installed_packages",
        description: "Lists the names of all installed R packages along with their titles.",
        inputSchema: {
          type: "object",
          properties: {}
        }
      },
      {
        name: "get_package_help_topics",
        description: "Returns the topic_id, title, and aliases fields for every topic in a package's documentation as a JSON-formatted string. Use this to find available documentation in a package.",
        inputSchema: {
          type: "object",
          properties: {
            package_name: {
              type: "string",
              description: "The exact name of the package, e.g. 'shiny'"
            }
          },
          required: ["package_name"]
        }
      },
      {
        name: "get_help_page",
        description: "Returns the complete help page for a package topic as plain text, including examples, descriptions, parameters, and return values.",
        inputSchema: {
          type: "object",
          properties: {
            package_name: {
              type: "string",
              description: "The exact name of the package, e.g. 'shiny'"
            },
            topic: {
              type: "string",
              description: "The topic_id or alias of the help page, e.g. 'withProgress' or 'incProgress'"
            }
          },
          required: ["package_name", "topic"]
        }
      },
      {
        name: "get_package_vignettes",
        description: "Lists all vignettes available in a specific R package as a JSON array of vignette names and titles. Vignettes are articles describing key concepts or features of an R package.",
        inputSchema: {
          type: "object",
          properties: {
            package_name: {
              type: "string",
              description: "The exact name of the package, e.g. 'shiny'"
            }
          },
          required: ["package_name"]
        }
      },
      {
        name: "get_vignette",
        description: "Retrieves a specific vignette from an R package in plain text format. Vignettes provide in-depth tutorials and explanations about package functionality.",
        inputSchema: {
          type: "object",
          properties: {
            package_name: {
              type: "string",
              description: "The exact name of the package, e.g. 'shiny'"
            },
            vignette_name: {
              type: "string",
              description: "The name of the vignette to retrieve. If omitted, retrieves the introductory vignette for the package."
            }
          },
          required: ["package_name"]
        }
      }
    ]
  };
});

const toolsCallSchema = z.object({
  method: z.literal("tools/call"),
  params: z.object({
    name: z.string(),
    arguments: z.any()
  })
});

server.setRequestHandler(toolsCallSchema, async (request) => {
  const { name, arguments: args } = request.params;
  
  try {
    let result: string;
    
    switch (name) {
      case "get_installed_packages":
        result = await executeR(`
          cat(btw::btw_tool_session_package_info(packages = "installed"))
        `);
        break;
        
      case "get_package_help_topics":
        result = await executeR(`
          cat(btw::btw_tool_docs_get_package_help_topics("${args.package_name}"))
        `);
        break;
        
      case "get_help_page":
        result = await executeR(`
          cat(btw::btw_tool_docs_get_help_page("${args.package_name}", "${args.topic}"))
        `);
        break;
        
      case "get_package_vignettes":
        result = await executeR(`
          cat(btw::btw_tool_docs_get_available_vignettes_in_package("${args.package_name}"))
        `);
        break;
        
      case "get_vignette":
        const vignetteName = args.vignette_name || args.package_name;
        result = await executeR(`
          cat(btw::btw_tool_docs_get_vignette_from_package("${args.package_name}", "${vignetteName}"))
        `);
        break;
        
      default:
        throw new Error(`Unknown tool: ${name}`);
    }
    
    return {
      content: [
        {
          type: "text",
          text: result
        }
      ]
    };
  } catch (error: unknown) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    return {
      isError: true,
      content: [
        {
          type: "text",
          text: `Error executing tool ${name}: ${errorMessage}`
        }
      ]
    };
  }
});

// Start the server
async function main() {
  try {
    const transport = new StdioServerTransport();
    await server.connect(transport);
  } catch (error: unknown) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    console.error("Error starting server:", errorMessage);
    process.exit(1);
  }
}

main();
